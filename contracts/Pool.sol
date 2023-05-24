// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./model/PoolModel.sol";
import "./common/NonReentrancy.sol";
import "./interface/IEventAggregator.sol";

contract Pool is Initializable, NonReentrancy, ContextUpgradeable, PoolModel {

    using SafeERC20Upgradeable for IERC20Upgradeable;
 
    uint256 constant SHARE_UNITS = 1e18;
    uint256 constant AMOUNT_PER_SHARE = 1e18;
    uint256 constant VOTE_EXPIRATION = 3 days;
    uint256 constant RATIO_BASE = 1e6;
    uint256 constant TIME_OFFSET = 4 days;

    constructor(bool isTest_) {
        if (!isTest_) {
            _disableInitializers();
        }
    }

    function initialize(
        address baseToken_,
        address tidalToken_,
        bool isTest_,
        address poolManager_,
        address[] calldata committeeMembers_
    ) public initializer {
        baseToken = baseToken_;
        tidalToken = tidalToken_;
        isTest = isTest_;
        committeeThreshold = 2;

        require(poolManager_ != address(0), "Empty poolManager");
        require(committeeMembers_.length >= 2, "At least 2 initial members");

        poolManager = poolManager_;
        for (uint256 i = 0; i < committeeMembers_.length; ++i) {
            address member = committeeMembers_[i];
            committeeArray.push(member);
            committeeIndexPlusOne[member] = committeeArray.length;
        }
    }

    modifier onlyPoolManager() {
        require(poolManager == _msgSender(), "Only pool manager");
        _;
    }

    modifier onlyTest() {
        require(isTest, "Only enabled in test environment");
        _;
    }

    modifier onlyCommittee() {
        require(committeeIndexPlusOne[_msgSender()] > 0, "Only committee");
        _;
    }

    // ** Time related functions.

    function setTimeExtra(uint256 timeExtra_) external onlyTest {
        timeExtra = timeExtra_;
    }

    function getCurrentWeek() public view returns(uint256) {
        return (block.timestamp + TIME_OFFSET + timeExtra) / (7 days);
    }

    function getNow() public view returns(uint256) {
        return block.timestamp + timeExtra;
    }

    function getWeekFromTime(uint256 time_) public pure returns(uint256) {
        return (time_ + TIME_OFFSET) / (7 days);
    }

    function getUnlockTime(
        uint256 time_,
        uint256 waitWeeks_
    ) public pure returns(uint256) {
        require(time_ + TIME_OFFSET > (7 days), "Time not large enough");
        return ((time_ + TIME_OFFSET) / (7 days) + waitWeeks_) * (7 days) - TIME_OFFSET;
    }

    // ** Event aggregator

    function setEventAggregator(
        address eventAggregator_
    ) external onlyPoolManager {
        require(eventAggregator_ != eventAggregator, "Value no difference");

        if (eventAggregator != address(0)) {
            IEventAggregator(eventAggregator).setEventAggregator(
                eventAggregator,
                eventAggregator_
            );
        }

        if (eventAggregator_ != address(0)) {
            IEventAggregator(eventAggregator_).setEventAggregator(
                eventAggregator,
                eventAggregator_
            );
        }

        eventAggregator = eventAggregator_;
    }

    // ** Pool and policy config.

    function getPool() external view noReenterView returns(
        uint256 withdrawWaitWeeks1_,
        uint256 withdrawWaitWeeks2_,
        uint256 policyWeeks_,
        uint256 withdrawFee_,
        uint256 managementFee1_,
        uint256 managementFee2_,
        uint256 minimumDepositAmount_,
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
        minimumDepositAmount_ = minimumDepositAmount;
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
        uint256 minimumDepositAmount_,
        bool enabled_,
        string calldata name_,
        string calldata terms_
    ) external onlyPoolManager {
        withdrawWaitWeeks1 = withdrawWaitWeeks1_;
        withdrawWaitWeeks2 = withdrawWaitWeeks2_;
        policyWeeks = policyWeeks_;
        withdrawFee = withdrawFee_;
        managementFee1 = managementFee1_;
        managementFee2 = managementFee2_;
        minimumDepositAmount = minimumDepositAmount_;
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
    ) external onlyPoolManager {
        require(index_ < policyArray.length, "Invalid index");
        require(collateralRatio_ > 0, "Should be non-zero");
        require(weeklyPremium_ < RATIO_BASE, "Should be less than 100%");

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
    ) external onlyPoolManager {
        require(collateralRatio_ > 0, "Should be non-zero");
        require(weeklyPremium_ < RATIO_BASE, "Should be less than 100%");

        policyArray.push(Policy({
            collateralRatio: collateralRatio_,
            weeklyPremium: weeklyPremium_,
            name: name_,
            terms: terms_
        }));
    }

    function getPolicyArrayLength() external view noReenterView returns(uint256) {
        return policyArray.length;
    }

    function getCollateralAmount() external view noReenterView returns(uint256) {
        return poolInfo.amountPerShare * (
            poolInfo.totalShare - poolInfo.pendingWithdrawShare) / SHARE_UNITS;
    }

    function getAvailableCapacity(
        uint256 policyIndex_,
        uint256 w_
    ) public view returns(uint256) {
        uint256 currentWeek = getCurrentWeek();
        uint256 amount = 0;
        uint256 w;

        if (w_ >= currentWeek + withdrawWaitWeeks1 || w_ < currentWeek) {
            return 0;
        } else {
            amount = poolInfo.amountPerShare * (
                poolInfo.totalShare - poolInfo.pendingWithdrawShare) / SHARE_UNITS;

            for (w = currentWeek - withdrawWaitWeeks1;
                 w < w_ - withdrawWaitWeeks1;
                 ++w) {
                amount -= poolInfo.amountPerShare * poolWithdrawMap[w] / SHARE_UNITS;
            }

            Policy storage policy = policyArray[policyIndex_];
            uint256 capacity = amount * RATIO_BASE / policy.collateralRatio;

            if (capacity > coveredMap[policyIndex_][w_]) {
                return capacity - coveredMap[policyIndex_][w_];
            } else {
                return 0;
            }
        }
    }

    function getCurrentAvailableCapacity(
        uint256 policyIndex_
    ) external view noReenterView returns(uint256) {
        uint256 w = getCurrentWeek();
        return getAvailableCapacity(policyIndex_, w);
    }

    function getTotalAvailableCapacity() external view noReenterView returns(uint256) {
        uint256 w = getCurrentWeek();

        uint256 total = 0;
        for (uint256 i = 0; i < policyArray.length; ++i) {
            total += getAvailableCapacity(i, w);
        }

        return total;
    }

    function getUserBaseAmount(address who_) external view noReenterView returns(uint256) {
        UserInfo storage userInfo = userInfoMap[who_];
        return poolInfo.amountPerShare * userInfo.share / SHARE_UNITS;
    }

    // ** Regular operations.

    // Anyone can be a buyer, and pay premium on certain policy for a few weeks.
    function buy(
        uint256 policyIndex_,
        uint256 amount_,
        uint256 maxPremium_,
        uint256 fromWeek_,
        uint256 toWeek_,
        string calldata notes_
    ) external noReenter {
        require(enabled, "Not enabled");

        require(toWeek_ > fromWeek_, "Not enough weeks");
        require(toWeek_ - fromWeek_ <= policyWeeks,
            "Too many weeks");
        require(fromWeek_ > getCurrentWeek(), "Buy next week");

        Policy storage policy = policyArray[policyIndex_];
        uint256 premium = amount_ * policy.weeklyPremium / RATIO_BASE;
        uint256 allPremium = premium * (toWeek_ - fromWeek_);

        require(allPremium <= maxPremium_, "Exceeds maxPremium_");

        uint256 maximumToCover = poolInfo.amountPerShare * (
            poolInfo.totalShare - poolInfo.pendingWithdrawShare) / SHARE_UNITS *
                    RATIO_BASE / policy.collateralRatio;

        for (uint256 w = fromWeek_; w < toWeek_; ++w) {
            incomeMap[policyIndex_][w] += premium;
            coveredMap[policyIndex_][w] += amount_;

            require(coveredMap[policyIndex_][w] <= maximumToCover,
                "Not enough to buy");

            Coverage storage entry = coverageMap[policyIndex_][w][_msgSender()];
            entry.amount += amount_;
            entry.premium += premium;
            entry.refunded = false;
        }

        IERC20Upgradeable(baseToken).safeTransferFrom(
            _msgSender(), address(this), allPremium);

        if (eventAggregator != address(0)) {
            IEventAggregator(eventAggregator).buy(
                _msgSender(),
                policyIndex_,
                amount_,
                fromWeek_,
                toWeek_,
                notes_
            );
        }
    }

    // Anyone just call this function once per week for every policy.
    function addPremium(uint256 policyIndex_) external noReenter {
        require(enabled, "Not enabled");

        uint256 week = getCurrentWeek();

        if (incomeMap[policyIndex_][week] == 0) {
            // Already added premium or no premium to add.
            return;
        }

        Policy storage policy = policyArray[policyIndex_];

        uint256 maximumToCover = poolInfo.amountPerShare * (
            poolInfo.totalShare - poolInfo.pendingWithdrawShare) / SHARE_UNITS *
                RATIO_BASE / policy.collateralRatio;

        uint256 allCovered = coveredMap[policyIndex_][week];

        if (allCovered > maximumToCover) {
            refundMap[policyIndex_][week] = incomeMap[policyIndex_][week] * (
                allCovered - maximumToCover) / allCovered;
            incomeMap[policyIndex_][week] -= refundMap[policyIndex_][week];
        }

        // Deducts management fee.
        uint256 totalIncome = incomeMap[policyIndex_][week];
        uint256 fee1 = totalIncome * managementFee1 / RATIO_BASE;
        uint256 fee2 = totalIncome * managementFee2 / RATIO_BASE;
        uint256 realIncome = totalIncome - fee1 - fee2;

        poolInfo.amountPerShare +=
            realIncome * SHARE_UNITS / poolInfo.totalShare;

        // Updates tidalPending (before Distributes fee1).
        UserInfo storage poolManagerInfo = userInfoMap[poolManager];
        uint256 accAmount = poolInfo.accTidalPerShare *
            poolManagerInfo.share / SHARE_UNITS;
        poolManagerInfo.tidalPending += accAmount - poolManagerInfo.tidalDebt;

        // Distributes fee1.
        uint256 fee1Share = fee1 * SHARE_UNITS / poolInfo.amountPerShare;
        poolManagerInfo.share += fee1Share;
        poolInfo.totalShare += fee1Share;

        // Updates tidalDebt.
        poolManagerInfo.tidalDebt = poolInfo.accTidalPerShare *
            poolManagerInfo.share / SHARE_UNITS;

        // Distributes fee2.
        IERC20Upgradeable(baseToken).safeTransfer(poolManager, fee2);

        incomeMap[policyIndex_][week] = 0;
    }

    // Anyone just call this function once per week for every policy.
    function refund(
        uint256 policyIndex_,
        uint256 week_,
        address who_
    ) external noReenter {
        require(refundMap[policyIndex_][week_] > 0, "Not ready to refund");

        Coverage storage coverage = coverageMap[policyIndex_][week_][who_];

        require(!coverage.refunded, "Already refunded");

        uint256 allCovered = coveredMap[policyIndex_][week_];
        uint256 amountToRefund = refundMap[policyIndex_][week_] *
            coverage.amount / allCovered;
        coverage.amount = coverage.amount *
            (coverage.premium - amountToRefund) / coverage.premium;
        coverage.refunded = true;

        IERC20Upgradeable(baseToken).safeTransfer(who_, amountToRefund);

        if (eventAggregator != address(0)) {
            IEventAggregator(eventAggregator).refund(
                policyIndex_,
                week_,
                who_,
                amountToRefund
            );
        }
    }

    // Anyone can be a seller, and deposit baseToken (e.g. USDC or WETH)
    // to the pool.
    function deposit(
        uint256 amount_
    ) external noReenter {
        require(enabled, "Not enabled");

        require(amount_ >= minimumDepositAmount, "Less than minimum");

        IERC20Upgradeable(baseToken).safeTransferFrom(
            _msgSender(), address(this), amount_);

        UserInfo storage userInfo = userInfoMap[_msgSender()];

        // Updates tidalPending.
        uint256 accAmount = poolInfo.accTidalPerShare *
            userInfo.share / SHARE_UNITS;
        userInfo.tidalPending += accAmount - userInfo.tidalDebt;

        if (poolInfo.totalShare == 0) {          
            poolInfo.amountPerShare = AMOUNT_PER_SHARE;
            poolInfo.totalShare = amount_ * SHARE_UNITS / AMOUNT_PER_SHARE;
            userInfo.share = poolInfo.totalShare;
        } else {
            uint256 shareToAdd =
                amount_ * SHARE_UNITS / poolInfo.amountPerShare;
            poolInfo.totalShare += shareToAdd;
            userInfo.share += shareToAdd;
        }

        // Updates tidalDebt.
        userInfo.tidalDebt = poolInfo.accTidalPerShare *
            userInfo.share / SHARE_UNITS;

        if (eventAggregator != address(0)) {
            IEventAggregator(eventAggregator).deposit(
                _msgSender(),
                amount_
            );
        }
    }

    function getUserAvailableWithdrawAmount(
        address who_
    ) external view noReenterView returns(uint256) {
        UserInfo storage userInfo = userInfoMap[who_];
        return poolInfo.amountPerShare * (
            userInfo.share - userInfo.pendingWithdrawShare) / SHARE_UNITS;
    }

    // Existing sellers can request to withdraw from the pool by shares.
    function withdraw(
        uint256 share_
    ) external noReenter {
        require(enabled, "Not enabled");

        UserInfo storage userInfo = userInfoMap[_msgSender()];

        require(userInfo.share >=
            userInfo.pendingWithdrawShare + share_, "Not enough");

        withdrawRequestMap[_msgSender()].push(WithdrawRequest({
            share: share_,
            time: getNow(),
            status: WithdrawRequestStatus.Created,
            succeeded: false
        }));

        userInfo.pendingWithdrawShare += share_;

        uint256 week = getCurrentWeek();
        poolWithdrawMap[week] += share_;

        if (eventAggregator != address(0)) {
            IEventAggregator(eventAggregator).withdraw(
                _msgSender(),
                withdrawRequestMap[_msgSender()].length - 1,
                share_
            );
        }
    }

    // Called after withdrawWaitWeeks1, by anyone (can be a script or by
    // seller himself).
    function withdrawPending(
        address who_,
        uint256 index_
    ) external noReenter {
        require(enabled, "Not enabled");

        require(index_ < withdrawRequestMap[who_].length, "No index");

        WithdrawRequest storage request = withdrawRequestMap[who_][index_];
        require(request.status == WithdrawRequestStatus.Created,
                "Wrong status");

        uint256 unlockTime = getUnlockTime(request.time, withdrawWaitWeeks1);
        require(getNow() > unlockTime, "Not ready yet");

        poolInfo.pendingWithdrawShare += request.share;

        request.status = WithdrawRequestStatus.Pending;

        if (eventAggregator != address(0)) {
            IEventAggregator(eventAggregator).withdrawPending(
                who_,
                index_
            );
        }
    }

    // Called after withdrawWaitWeeks2, by anyone.
    function withdrawReady(
        address who_,
        uint256 index_
    ) external noReenter {
        require(enabled, "Not enabled");

        require(index_ < withdrawRequestMap[who_].length, "No index");

        WithdrawRequest storage request = withdrawRequestMap[who_][index_];
        require(request.status == WithdrawRequestStatus.Pending,
                "Wrong status");

        uint256 waitWeeks = withdrawWaitWeeks1 + withdrawWaitWeeks2;
        uint256 unlockTime = getUnlockTime(request.time, waitWeeks);
        require(getNow() > unlockTime, "Not ready yet");

        UserInfo storage userInfo = userInfoMap[who_];

        if (userInfo.share >= request.share) {
            // Updates tidalPending.
            uint256 accAmount = poolInfo.accTidalPerShare *
                userInfo.share / SHARE_UNITS;
            userInfo.tidalPending += accAmount - userInfo.tidalDebt;

            userInfo.share -= request.share;
            poolInfo.totalShare -= request.share;

            // Updates tidalDebt.
            userInfo.tidalDebt = poolInfo.accTidalPerShare *
                userInfo.share / SHARE_UNITS;

            uint256 amount = poolInfo.amountPerShare *
                request.share / SHARE_UNITS;

            // A withdrawFee goes to everyone.
            uint256 fee = amount * withdrawFee / RATIO_BASE;
            IERC20Upgradeable(baseToken).safeTransfer(who_, amount - fee);
            poolInfo.amountPerShare += fee * SHARE_UNITS / poolInfo.totalShare;

            request.succeeded = true;
        } else {
            request.succeeded = false;
        }

        request.status = WithdrawRequestStatus.Executed;

        // Reduce pendingWithdrawShare.
        userInfo.pendingWithdrawShare -= request.share;
        poolInfo.pendingWithdrawShare -= request.share;

        if (eventAggregator != address(0)) {
            IEventAggregator(eventAggregator).withdrawReady(
                who_,
                index_,
                request.succeeded
            );
        }
    }

    function withdrawRequestCount(
        address who_
    ) external view noReenterView returns(uint256) {
        return withdrawRequestMap[who_].length;
    }

    // Anyone can add tidal to the pool as incentative any time.
    function addTidal(uint256 amount_) external noReenter {
        IERC20Upgradeable(tidalToken).safeTransferFrom(
            _msgSender(), address(this), amount_);

        poolInfo.accTidalPerShare +=
            amount_ * SHARE_UNITS / poolInfo.totalShare;
    }

    function getUserTidalAmount(address who_) external view noReenterView returns(uint256) {
        UserInfo storage userInfo = userInfoMap[who_];
        return poolInfo.accTidalPerShare * userInfo.share / SHARE_UNITS +
            userInfo.tidalPending - userInfo.tidalDebt;
    }

    // Sellers can withdraw TIDAL, which are bonuses, from the pool.
    function withdrawTidal() external noReenter {
        require(enabled, "Not enabled");

        UserInfo storage userInfo = userInfoMap[_msgSender()];
        uint256 accAmount = poolInfo.accTidalPerShare *
            userInfo.share / SHARE_UNITS;
        uint256 tidalAmount = userInfo.tidalPending +
            accAmount - userInfo.tidalDebt;

        IERC20Upgradeable(tidalToken).safeTransfer(_msgSender(), tidalAmount);

        userInfo.tidalPending = 0;
        userInfo.tidalDebt = accAmount;
    }

    // ** Emergency

    // Pool manager can enable or disable the pool in emergency.
    function enablePool(bool enabled_) external onlyPoolManager {
        enabled = enabled_;

        if (eventAggregator != address(0)) {
            IEventAggregator(eventAggregator).enablePool(
                enabled_
            );
        }
    }

    // ** Claim (and other type of requests), vote, and execute.

    // ** Operation #1, claim
    function claim(
        uint256 policyIndex_,
        uint256 amount_,
        address receipient_
    ) external onlyPoolManager {
        committeeRequestArray.push(CommitteeRequest({
            time: getNow(),
            vote: 0,
            executed: false,
            operation: CommitteeRequestType.Claim,
            data: abi.encode(amount_, receipient_)
        }));

        if (eventAggregator != address(0)) {
            IEventAggregator(eventAggregator).claim(
                policyIndex_,
                amount_,
                receipient_
            );
        }
    }

    // ** Operation #2, changePoolManager
    function changePoolManager(
        address poolManager_
    ) external onlyCommittee {
        committeeRequestArray.push(CommitteeRequest({
            time: getNow(),
            vote: 0,
            executed: false,
            operation: CommitteeRequestType.ChangePoolManager,
            data: abi.encode(poolManager_)
        }));

        if (eventAggregator != address(0)) {
            IEventAggregator(eventAggregator).changePoolManager(
                poolManager_
            );
        }
    }

    // ** Operation #3, addToCommittee
    function addToCommittee(
        address who_
    ) external onlyCommittee {
        require(committeeIndexPlusOne[who_] == 0, "Existing committee member");

        committeeRequestArray.push(CommitteeRequest({
            time: getNow(),
            vote: 0,
            executed: false,
            operation: CommitteeRequestType.AddToCommittee,
            data: abi.encode(who_)
        }));

        if (eventAggregator != address(0)) {
            IEventAggregator(eventAggregator).addToCommittee(
                who_
            );
        }
    }

    // ** Operation #4, removeFromCommittee
    function removeFromCommittee(
        address who_
    ) external onlyCommittee {
        require(committeeArray.length > committeeThreshold,
                "Not enough members");

        committeeRequestArray.push(CommitteeRequest({
            time: getNow(),
            vote: 0,
            executed: false,
            operation: CommitteeRequestType.RemoveFromCommittee,
            data: abi.encode(who_)
        }));

        if (eventAggregator != address(0)) {
            IEventAggregator(eventAggregator).removeFromCommittee(
                who_
            );
        }
    }

    // ** Operation #5, changeCommitteeThreshold
    function changeCommitteeThreshold(
        uint256 threshold_
    ) external onlyCommittee {
        require(threshold_ >= 2, "Invalid threshold");
        require(threshold_ <= committeeArray.length,
                "Threshold more than member count");

        committeeRequestArray.push(CommitteeRequest({
            time: getNow(),
            vote: 0,
            executed: false,
            operation: CommitteeRequestType.ChangeCommitteeThreshold,
            data: abi.encode(threshold_)
        }));

        if (eventAggregator != address(0)) {
            IEventAggregator(eventAggregator).changeCommitteeThreshold(
                threshold_
            );
        }
    }

    // Committee members can vote on any of the above 5 types of operations.
    function voteAndSupport(
        uint256 requestIndex_
    ) external onlyCommittee noReenter {
        require(requestIndex_ < committeeRequestArray.length, "Invalid index");

        require(!committeeVote[_msgSender()][requestIndex_],
                "Already supported");
        committeeVote[_msgSender()][requestIndex_] = true;

        CommitteeRequest storage cr = committeeRequestArray[requestIndex_];

        require(getNow() < cr.time + VOTE_EXPIRATION,
                "Already expired");
        require(!cr.executed, "Already executed");
        cr.vote += 1;

        if (eventAggregator != address(0)) {
            IEventAggregator(eventAggregator).voteAndSupport(
                requestIndex_
            );
        }

        if (cr.vote >= committeeThreshold) {
            _execute(requestIndex_);
        }
    }

    // Anyone can execute an operation request that has received enough
    // approving votes.
    function _execute(uint256 requestIndex_) private {
        require(requestIndex_ < committeeRequestArray.length, "Invalid index");

        CommitteeRequest storage cr = committeeRequestArray[requestIndex_];

        require(cr.vote >= committeeThreshold, "Not enough votes");
        require(getNow() < cr.time + VOTE_EXPIRATION,
                "Already expired");
        require(!cr.executed, "Already executed");

        cr.executed = true;

        if (cr.operation == CommitteeRequestType.Claim) {
            (uint256 amount, address receipient) = abi.decode(
                cr.data, (uint256, address));
            _executeClaim(amount, receipient);
        } else if (cr.operation == CommitteeRequestType.ChangePoolManager) {
            address poolManager = abi.decode(cr.data, (address));
            _executeChangePoolManager(poolManager);
        } else if (cr.operation == CommitteeRequestType.AddToCommittee) {
            address newMember = abi.decode(cr.data, (address));
            _executeAddToCommittee(newMember);
        } else if (cr.operation == CommitteeRequestType.RemoveFromCommittee) {
            address oldMember = abi.decode(cr.data, (address));
            _executeRemoveFromCommittee(oldMember);
        } else if (cr.operation ==
                CommitteeRequestType.ChangeCommitteeThreshold) {
            uint256 threshold = abi.decode(cr.data, (uint256));
            _executeChangeCommitteeThreshold(threshold);
        }

        if (eventAggregator != address(0)) {
            IEventAggregator(eventAggregator).execute(
                requestIndex_,
                uint256(cr.operation),
                cr.data
            );
        }
    }

    function _executeClaim(
        uint256 amount_,
        address receipient_
    ) private {
        IERC20Upgradeable(baseToken).safeTransfer(receipient_, amount_);

        poolInfo.amountPerShare -=
            amount_ * SHARE_UNITS / poolInfo.totalShare;
    }

    function _executeChangePoolManager(address poolManager_) private {
        poolManager = poolManager_;
    }

    function _executeAddToCommittee(address who_) private {
        require(committeeIndexPlusOne[who_] == 0, "Existing committee member");
        committeeArray.push(who_);
        committeeIndexPlusOne[who_] = committeeArray.length;
    }

    function _executeRemoveFromCommittee(address who_) private {
        require(committeeArray.length > committeeThreshold,
                "Not enough members");
        require(committeeIndexPlusOne[who_] > 0,
                "Non-existing committee member");
        if (committeeIndexPlusOne[who_] != committeeArray.length) {
            address lastOne = committeeArray[committeeArray.length - 1];
            committeeIndexPlusOne[lastOne] = committeeIndexPlusOne[who_];
            committeeArray[committeeIndexPlusOne[who_] - 1] = lastOne;
        }

        committeeIndexPlusOne[who_] = 0;
        committeeArray.pop();
    }

    function _executeChangeCommitteeThreshold(uint256 threshold_) private {
        require(threshold_ >= 2, "Invalid threshold");
        require(threshold_ <= committeeArray.length,
                "Threshold more than member count");
        committeeThreshold = threshold_;
    }

    function getCommitteeRequestLength() external view noReenterView returns(uint256) {
        return committeeRequestArray.length;
    }

    function getCommitteeRequestArray(
        uint256 limit_,
        uint256 offset_
    ) external view noReenterView returns(CommitteeRequest[] memory) {
        if (committeeRequestArray.length <= offset_) {
            return new CommitteeRequest[](0);
        }

        uint256 leftSideOffset = committeeRequestArray.length - offset_;
        CommitteeRequest[] memory result =
            new CommitteeRequest[](
                leftSideOffset < limit_ ? leftSideOffset : limit_);

        uint256 i = 0;
        while (i < limit_ && leftSideOffset > 0) {
            leftSideOffset -= 1;
            result[i] = committeeRequestArray[leftSideOffset];
            i += 1;
        }

        return result;
    }
}
