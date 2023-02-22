// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./interfaces/IPool.sol";

import "./common/NonReentrancy.sol";


contract Pool is IPool, NonReentrancy, Ownable {

    using SafeERC20 for IERC20;
    using SafeMath for uint256;
 
    uint256 constant SHARE_UNITS = 1e18;
    uint256 constant AMOUNT_PER_SHARE = 1e24;
    uint256 constant VOTE_EXPIRATION = 3 days;
    uint256 constant RATIO_BASE = 1e6;

    bool public isTest;

    address public baseToken;
    address public tidalToken;

    uint256 public withdrawWaitWeeks1;
    uint256 public withdrawWaitWeeks2;
    uint256 public policyWeeks;

    // withdrawFee is a percentage.
    uint256 public withdrawFee;

    // managementFee1 is a percentage and charged as shares.
    uint256 public managementFee1;

    // managementFee2 is a percentage and charged as tokens.
    uint256 public managementFee2;

    bool public enabled;
    string public name;
    string public terms;

    bool public locked;

    struct Policy {
        uint256 collateralRatio;
        uint256 weeklyPremium;
        string name;
        string terms;
    }

    Policy[] public policyArray;

    // policy index => week => amount
    mapping(uint256 => mapping(uint256 => uint256)) public coveredMap;

    struct PoolInfo {
        // Base token amount
        uint256 totalShare;
        uint256 amountPerShare;

        // Pending withdraw amount
        uint256 pendingWithdrawAmount;

        // Tidal Rewards
        uint256 accTidalPerShare;
    }

    PoolInfo public poolInfo;

    struct UserInfo {
        // Base token amount
        uint256 share;

        // Pending withdraw amount
        uint256 pendingWithdrawAmount;

        // Tidal Rewards
        uint256 tidalPending;
        uint256 tidalDebt;
    }

    mapping(address => UserInfo) public userInfoMap;

    mapping(uint256 => uint256) public poolWithdrawMap;

    struct WithdrawRequest {
        uint256 amount;
        uint256 time;
        bool pending;
        bool executed;
        bool succeeded;
    }

    mapping(address => WithdrawRequest[]) public withdrawRequestMap;

    // policy index => week => Income
    mapping(uint256 => mapping(uint256 => uint256)) public incomeMap;

    struct Coverage {
        uint256 amount;
        uint256 premium;
        bool refunded;
    }

    // policy index => week => who => Coverage
    mapping(uint256 => mapping(uint256 => mapping(
        address => Coverage))) public coverageMap;

    mapping(uint256 => mapping(uint256 => uint256)) public refundMap;

    // Claiming related data.

    struct ClaimRequest {
        uint256 policyIndex;
        uint256 amount;
        address receipient;
        uint256 time;
        uint256 vote;
        bool executed;
    }

    ClaimRequest[] public claimRequestArray;

    function getClaimRequestLength() external view returns(uint256) {
        return claimRequestArray.length;
    }

    function getClaimRequestArray(
        uint256 limit_,
        uint256 offset_
    ) external view returns(ClaimRequest[] memory) {
        if (claimRequestArray.length <= offset_) {
            return new ClaimRequest[](0);
        }

        uint256 leftSideOffset = claimRequestArray.length.sub(offset_);
        ClaimRequest[] memory result =
            new ClaimRequest[](
                leftSideOffset < limit_ ? leftSideOffset : limit_);

        uint256 i = 0;
        while (i < limit_ && leftSideOffset > 0) {
            leftSideOffset = leftSideOffset.sub(1);
            result[i] = claimRequestArray[leftSideOffset];
            i = i.add(1);
        }

        return result;
    }

    mapping(address => mapping(uint256 => bool)) committeeVote;

    // Access control.

    address public admin;

    mapping(address => uint256) public committeeIndexPlusOne;
    address[] public committeeArray;
    uint256 public committeeThreshold = 2;

    // Time.

    uint256 public offset = 4 days;
    uint256 public timeExtra;

    function setTimeExtra(uint256 timeExtra_) external onlyTest {
        timeExtra = timeExtra_;
    }

    function getCurrentWeek() public view returns(uint256) {
        return (now + offset + timeExtra) / (7 days);
    }

    function getNow() public view returns(uint256) {
        return now + timeExtra;
    }

    function getWeekFromTime(uint256 time_) public view returns(uint256) {
        return (time_ + offset) / (7 days);
    }

    function getUnlockTime(
        uint256 time_,
        uint256 waitWeeks_
    ) public view returns(uint256) {
        require(time_ + offset > (7 days), "Time not large enough");
        return ((time_ + offset) / (7 days) + waitWeeks_) * (7 days) - offset;
    }

    event Buy(
        address indexed who_,
        uint256 indexed policyIndex_,
        uint256 amount_,
        uint256 fromWeek_,
        uint256 toWeek_
    );

    event Deposit(
        address indexed who_,
        uint256 amount_
    );

    event Withdraw(
        address indexed who_,
        uint256 amount_
    );

    event Refund(
        uint256 indexed policyIndex_,
        uint256 indexed week_,
        address indexed who_,
        uint256 amount_
    );

    constructor(address baseToken_, address tidalToken_, bool isTest_) public {
        baseToken = baseToken_;
        tidalToken = tidalToken_;
        isTest = isTest_;
    }

    modifier onlyAdmin() {
        require(admin == _msgSender(), "Only admin");
        _;
    }

    modifier onlyTest() {
        require(isTest, "Only enabled in test environment");
        _;
    }

    function setAdmin(address admin_) public onlyOwner {
        admin = admin_;
    }

    modifier onlyCommittee() {
        require(committeeIndexPlusOne[_msgSender()] > 0, "Only committee");
        _;
    }

    function addToCommittee(address who_) external onlyOwner {
        require(committeeIndexPlusOne[who_] == 0, "Existing committee member");
        committeeArray.push(who_);
        committeeIndexPlusOne[who_] = committeeArray.length;
    }

    function removeFromCommittee(address who_) external onlyOwner {
        require(committeeIndexPlusOne[who_] > 0,
                "Non-existing committee member");
        if (committeeIndexPlusOne[who_] != committeeArray.length) {
            address lastOne = committeeArray[committeeArray.length.sub(1)];
            committeeIndexPlusOne[lastOne] = committeeIndexPlusOne[who_];
            committeeArray[committeeIndexPlusOne[who_].sub(1)] = lastOne;
            committeeIndexPlusOne[who_] = 0;
        }

        committeeArray.pop();
    }

    function setCommitteeThreshold(uint256 threshold_) external onlyOwner {
        committeeThreshold = threshold_;
    }

    function getPool() external view returns(
        uint256 withdrawWaitWeeks1_,
        uint256 withdrawWaitWeeks2_,
        uint256 policyWeeks_,
        uint256 withdrawFee_,
        uint256 managementFee1_,
        uint256 managementFee2_,
        bool enabled_,
        string memory name_,
        string memory terms_
    ) {
        withdrawWaitWeeks1_ = withdrawWaitWeeks1;
        withdrawWaitWeeks2_ = withdrawWaitWeeks2;
        policyWeeks_ = policyWeeks;
        withdrawFee_ = withdrawFee;
        managementFee1_ = managementFee1;
        managementFee2_ = managementFee2;
        enabled_ = enabled;
        name_ = name;
        terms_ = terms;
    }

    function setPool(
        uint256 withdrawWaitWeeks1_,
        uint256 withdrawWaitWeeks2_,
        uint256 policyWeeks_,
        uint256 withdrawFee_,
        uint256 managementFee1_,
        uint256 managementFee2_,
        bool enabled_,
        string calldata name_,
        string calldata terms_
    ) external onlyAdmin {
        withdrawWaitWeeks1 = withdrawWaitWeeks1_;
        withdrawWaitWeeks2 = withdrawWaitWeeks2_;
        policyWeeks = policyWeeks_;
        withdrawFee = withdrawFee_;
        managementFee1 = managementFee1_;
        managementFee2 = managementFee2_;
        enabled = enabled_;
        name = name_;
        terms = terms_;
    }

    function setPolicy(
        uint256 index_,
        uint256 collateralRatio_,
        uint256 weeklyPremium_,
        string calldata name_,
        string calldata terms_
    ) external onlyAdmin {
        Policy storage policy = policyArray[index_];
        policy.collateralRatio = collateralRatio_;
        policy.weeklyPremium = weeklyPremium_;
        policy.name = name_;
        policy.terms = terms_;
    }

    function addPolicy(
        uint256 collateralRatio_,
        uint256 weeklyPremium_,
        string calldata name_,
        string calldata terms_
    ) external onlyAdmin {
        policyArray.push(Policy({
            collateralRatio: collateralRatio_,
            weeklyPremium: weeklyPremium_,
            name: name_,
            terms: terms_
        }));
    }

    function getPolicyArrayLength() external view returns(uint256) {
        return policyArray.length;
    }

    function getCollateralAmount() external view returns(uint256) {
        return poolInfo.amountPerShare.mul(
            poolInfo.totalShare).div(SHARE_UNITS).sub(
                poolInfo.pendingWithdrawAmount);
    }

    function getAvailableCapacity(
        uint256 policyIndex_,
        uint256 w_
    ) public view returns(uint256) {
        uint256 currentWeek = getCurrentWeek();
        uint256 amount = 0;
        uint256 w;

        if (w_ >= currentWeek.add(withdrawWaitWeeks1) || w_ < currentWeek) {
            return 0;
        } else {
            amount = poolInfo.amountPerShare.mul(
                poolInfo.totalShare).div(SHARE_UNITS).sub(
                    poolInfo.pendingWithdrawAmount);

            for (w = currentWeek.sub(withdrawWaitWeeks1);
                 w < w_.sub(withdrawWaitWeeks1);
                 ++w) {
                amount = amount.sub(poolWithdrawMap[w]);
            }

            Policy storage policy = policyArray[policyIndex_];
            return amount.mul(RATIO_BASE).div(policy.collateralRatio).sub(
                coveredMap[policyIndex_][w_]);
        }
    }

    function getCurrentAvailableCapacity(
        uint256 policyIndex_
    ) external view returns(uint256) {
        uint256 w = getCurrentWeek();
        return getAvailableCapacity(policyIndex_, w);
    }

    function getTotalAvailableCapacity() external view returns(uint256) {
        uint256 w = getCurrentWeek();

        uint256 total = 0;
        for (uint256 i = 0; i < policyArray.length; ++i) {
            total += getAvailableCapacity(i, w);
        }

        return total;
    }

    function getUserBaseAmount(address who_) external view returns(uint256) {
        UserInfo storage userInfo = userInfoMap[who_];
        return poolInfo.amountPerShare.mul(userInfo.share).div(SHARE_UNITS);
    }

    function buy(
        uint256 policyIndex_,
        uint256 amount_,
        uint256 fromWeek_,
        uint256 toWeek_
    ) external {
        require(enabled && !locked, "Not enabled or unlocked");

        require(toWeek_ > fromWeek_, "Not enough weeks");
        require(toWeek_.sub(fromWeek_) <= policyWeeks,
            "Too many weeks");
        require(fromWeek_ > getCurrentWeek(), "Buy next week");

        Policy storage policy = policyArray[policyIndex_];
        uint256 premium = amount_.mul(policy.weeklyPremium).div(RATIO_BASE);
        uint256 allPremium = premium.mul(toWeek_.sub(fromWeek_));

        uint256 maximumToCover = poolInfo.amountPerShare.mul(
            poolInfo.totalShare).div(SHARE_UNITS).sub(
                poolInfo.pendingWithdrawAmount).mul(
                    RATIO_BASE).div(policy.collateralRatio);

        for (uint256 w = fromWeek_; w < toWeek_; ++w) {
            incomeMap[policyIndex_][w] =
                incomeMap[policyIndex_][w].add(premium);
            coveredMap[policyIndex_][w] =
                coveredMap[policyIndex_][w].add(amount_);

            require(coveredMap[policyIndex_][w] <= maximumToCover,
                "Not enough to buy");

            coverageMap[policyIndex_][w][_msgSender()] = Coverage({
                amount: amount_,
                premium: premium,
                refunded: false
            });
        }

        IERC20(baseToken).safeTransferFrom(
            _msgSender(), address(this), allPremium);

        emit Buy(
            _msgSender(),
            policyIndex_,
            amount_,
            fromWeek_,
            toWeek_
        );
    }

    function refund(
        uint256 policyIndex_,
        uint256 week_,
        address who_
    ) external {
        Coverage storage coverage = coverageMap[policyIndex_][week_][who_];

        require(!coverage.refunded, "Already refunded");

        uint256 allCovered = coveredMap[policyIndex_][week_];
        uint256 amountToRefund = refundMap[policyIndex_][week_].mul(
            coverage.amount).div(allCovered);
        coverage.amount = coverage.amount.mul(
            coverage.premium.sub(amountToRefund)).div(coverage.premium);
        coverage.refunded = true;

        IERC20(baseToken).safeTransfer(who_, amountToRefund);

        emit Refund(policyIndex_, week_, who_, amountToRefund);
    }

    // Anyone just call this function once per week for every policy.
    function addPremium(uint256 policyIndex_) external {
        require(enabled && !locked, "Not enabled or unlocked");

        uint256 week = getCurrentWeek();

        Policy storage policy = policyArray[policyIndex_];

        uint256 maximumToCover = poolInfo.amountPerShare.mul(
            poolInfo.totalShare).div(SHARE_UNITS).sub(
                poolInfo.pendingWithdrawAmount).mul(
                    RATIO_BASE).div(policy.collateralRatio);

        uint256 allCovered = coveredMap[policyIndex_][week];

        if (allCovered > maximumToCover) {
            refundMap[policyIndex_][week] = incomeMap[policyIndex_][week].mul(
                allCovered.sub(maximumToCover)).div(allCovered);
            incomeMap[policyIndex_][week] = incomeMap[policyIndex_][week].sub(
                refundMap[policyIndex_][week]);
        }

        // Deducts management fee.
        uint256 totalIncome = incomeMap[policyIndex_][week];
        uint256 fee1 = totalIncome.mul(managementFee1).div(RATIO_BASE);
        uint256 fee2 = totalIncome.mul(managementFee2).div(RATIO_BASE);
        uint256 realIncome = totalIncome.sub(fee1).sub(fee2);

        poolInfo.amountPerShare = poolInfo.amountPerShare.add(
            realIncome.mul(SHARE_UNITS).div(poolInfo.totalShare));

        // Distributes fee1.
        UserInfo storage adminInfo = userInfoMap[admin];
        uint256 fee1Share = fee1.mul(SHARE_UNITS).div(poolInfo.amountPerShare);
        adminInfo.share = adminInfo.share.add(fee1Share);
        poolInfo.totalShare = poolInfo.totalShare.add(fee1Share);

        // Distributes fee2.
        IERC20(baseToken).safeTransfer(admin, fee2);

        incomeMap[policyIndex_][week] = 0;
    }

    function deposit(
        uint256 amount_
    ) external {
        require(enabled && !locked, "Not enabled or unlocked");

        require(amount_ >= AMOUNT_PER_SHARE / 1000000, "Less than minimum");

        IERC20(baseToken).safeTransferFrom(
            _msgSender(), address(this), amount_);

        _updateUserTidal(_msgSender());

        UserInfo storage userInfo = userInfoMap[_msgSender()];

        if (poolInfo.totalShare == 0) {          
            poolInfo.amountPerShare = AMOUNT_PER_SHARE;
            poolInfo.totalShare = amount_.mul(SHARE_UNITS).div(AMOUNT_PER_SHARE);
            userInfo.share = poolInfo.totalShare;
        } else {
            uint256 shareToAdd =
                amount_.mul(SHARE_UNITS).div(poolInfo.amountPerShare);
            poolInfo.totalShare = poolInfo.totalShare.add(shareToAdd);
            userInfo.share = userInfo.share.add(shareToAdd);
        }

        emit Deposit(_msgSender(), amount_);
    }

    function getUserAvailableWithdrawAmount(
        address who_
    ) external view returns(uint256) {
        UserInfo storage userInfo = userInfoMap[who_];
        uint256 userBaseAmount =
            poolInfo.amountPerShare.mul(userInfo.share).div(SHARE_UNITS);
        return userBaseAmount.sub(
                userInfo.pendingWithdrawAmount);
    }

    function withdraw(
        uint256 amount_
    ) external {
        require(enabled && !locked, "Not enabled or unlocked");

        UserInfo storage userInfo = userInfoMap[_msgSender()];
        uint256 userBaseAmount =
            poolInfo.amountPerShare.mul(userInfo.share).div(SHARE_UNITS);
        require(userBaseAmount >=
            userInfo.pendingWithdrawAmount.add(amount_), "Not enough");

        withdrawRequestMap[_msgSender()].push(WithdrawRequest({
            amount: amount_,
            time: getNow(),
            pending: false,
            executed: false,
            succeeded: false
        }));

        userInfo.pendingWithdrawAmount = userInfo.pendingWithdrawAmount.add(
            amount_);

        uint256 week = getCurrentWeek();
        poolWithdrawMap[week] = poolWithdrawMap[week].add(amount_);

        emit Withdraw(_msgSender(), amount_);
    }

    // Called after withdrawWaitWeeks1
    function withdrawPending(
        address who_,
        uint256 index_
    ) external {
        require(enabled && !locked, "Not enabled or unlocked");

        require(index_ < withdrawRequestMap[who_].length, "No index");

        WithdrawRequest storage request = withdrawRequestMap[who_][index_];
        require(!request.pending, "Already pending");

        uint256 unlockTime = getUnlockTime(request.time, withdrawWaitWeeks1);
        require(getNow() > unlockTime, "Not ready yet");

        poolInfo.pendingWithdrawAmount = poolInfo.pendingWithdrawAmount.add(
            request.amount);

        uint256 week = getWeekFromTime(request.time);
        poolWithdrawMap[week] = poolWithdrawMap[week].sub(request.amount);

        request.pending = true;
    }

    // Called after withdrawWaitWeeks2
    function withdrawReady(
        address who_,
        uint256 index_
    ) external {
        require(enabled && !locked, "Not enabled or unlocked");

        require(index_ < withdrawRequestMap[who_].length, "No index");

        WithdrawRequest storage request = withdrawRequestMap[who_][index_];
        require(!request.executed, "Already executed");
        require(request.pending, "Not pending yet");

        uint256 waitWeeks = withdrawWaitWeeks1.add(withdrawWaitWeeks2);
        uint256 unlockTime = getUnlockTime(request.time, waitWeeks);
        require(getNow() > unlockTime, "Not ready yet");

        UserInfo storage userInfo = userInfoMap[who_];
        if (poolInfo.amountPerShare.mul(userInfo.share).div(SHARE_UNITS) >=
                request.amount) {
            _updateUserTidal(who_);

            userInfo.share = poolInfo.amountPerShare.mul(
                userInfo.share).sub(request.amount.mul(SHARE_UNITS)).div(
                    poolInfo.amountPerShare);
            poolInfo.totalShare = poolInfo.amountPerShare.mul(
                poolInfo.totalShare).sub(request.amount.mul(SHARE_UNITS)).div(
                    poolInfo.amountPerShare);

            // A withdrawFee goes to admin
            uint256 fee = request.amount.mul(withdrawFee).div(RATIO_BASE);
            IERC20(baseToken).safeTransfer(who_, request.amount.sub(fee));
            IERC20(baseToken).safeTransfer(admin, fee);

            request.succeeded = true;
        } else {
            request.succeeded = false;
        }

        request.executed = true;

        // Reduce pendingWithdrawAmount.
        userInfo.pendingWithdrawAmount = userInfo.pendingWithdrawAmount.sub(
            request.amount);
        poolInfo.pendingWithdrawAmount = poolInfo.pendingWithdrawAmount.sub(
            request.amount);
    }

    function withdrawRequestCount(
        address who_
    ) external view returns(uint256) {
        return withdrawRequestMap[who_].length;
    }

    // Anyone can add tidal to the pool as incentative any time.
    function addTidal(uint256 amount_) external {
        IERC20(tidalToken).safeTransferFrom(
            _msgSender(), address(this), amount_);

        poolInfo.accTidalPerShare = poolInfo.accTidalPerShare.add(
            amount_.mul(SHARE_UNITS)).div(poolInfo.totalShare);
    }

    function _updateUserTidal(address who_) private {
        UserInfo storage userInfo = userInfoMap[who_];
        uint256 accAmount = poolInfo.accTidalPerShare.add(
            userInfo.share).div(SHARE_UNITS);
        userInfo.tidalPending = userInfo.tidalPending.add(
            accAmount.sub(userInfo.tidalDebt));
        userInfo.tidalDebt = accAmount;
    }

    function getUserTidalAmount(address who_) external view returns(uint256) {
        UserInfo storage userInfo = userInfoMap[who_];
        return poolInfo.accTidalPerShare.mul(
            userInfo.share).div(SHARE_UNITS).add(
                userInfo.tidalPending).sub(userInfo.tidalDebt);
    }

    function withdrawTidal() external {
        require(enabled && !locked, "Not enabled or unlocked");

        UserInfo storage userInfo = userInfoMap[_msgSender()];
        uint256 accAmount = poolInfo.accTidalPerShare.add(userInfo.share);
        uint256 tidalAmount = userInfo.tidalPending.add(
            accAmount).sub(userInfo.tidalDebt);

        IERC20(tidalToken).safeTransfer(_msgSender(), tidalAmount);

        userInfo.tidalPending = 0;
        userInfo.tidalDebt = accAmount;
    }

    function lockPool() external onlyAdmin {
        locked = true;
    }

    function unlockPool() external onlyAdmin {
        locked = false;
    }

    function claim(
        uint256 policyIndex_,
        uint256 amount_,
        address receipient_
    ) external onlyAdmin {
        claimRequestArray.push(ClaimRequest({
            policyIndex: policyIndex_,
            amount: amount_,
            receipient: receipient_,
            time: getNow(),
            vote: 0,
            executed: false
        }));
    }

    function vote(
        uint256 claimIndex_,
        bool support_
    ) external onlyCommittee {
        if (!support_) {
            return;
        }

        require(claimIndex_ < claimRequestArray.length, "Invalid index");

        require(!committeeVote[_msgSender()][claimIndex_],
                "Already supported");
        committeeVote[_msgSender()][claimIndex_] = true;

        ClaimRequest storage cr = claimRequestArray[claimIndex_];

        require(getNow() < cr.time.add(VOTE_EXPIRATION),
                "Already expired");
        require(!cr.executed, "Already executed");
        cr.vote = cr.vote.add(1);
    }

    function execute(uint256 claimIndex_) external {
        require(claimIndex_ < claimRequestArray.length, "Invalid index");

        ClaimRequest storage cr = claimRequestArray[claimIndex_];

        require(cr.vote >= committeeThreshold, "Not enough votes");
        require(getNow() < cr.time.add(VOTE_EXPIRATION),
                "Already expired");
        require(!cr.executed, "Already executed");

        cr.executed = true;

        IERC20(baseToken).safeTransfer(cr.receipient, cr.amount);

        poolInfo.amountPerShare = poolInfo.amountPerShare.sub(
            cr.amount.mul(SHARE_UNITS).div(poolInfo.totalShare));
    }
}
