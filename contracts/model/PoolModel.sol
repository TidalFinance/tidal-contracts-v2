// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

contract PoolModel {

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

    // Minimum deposit amount.
    uint256 public minimumDepositAmount;

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

        // Pending withdraw share
        uint256 pendingWithdrawShare;

        // Tidal Rewards
        uint256 accTidalPerShare;
    }

    PoolInfo public poolInfo;

    struct UserInfo {
        // Base token amount
        uint256 share;

        // Pending withdraw share
        uint256 pendingWithdrawShare;

        // Tidal Rewards
        uint256 tidalPending;
        uint256 tidalDebt;
    }

    mapping(address => UserInfo) public userInfoMap;

    // week => share
    mapping(uint256 => uint256) public poolWithdrawMap;

    enum WithdrawRequestStatus {
        Created,
        Pending,
        Executed
    }

    struct WithdrawRequest {
        uint256 share;
        uint256 time;
        WithdrawRequestStatus status;
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

    // Committee request.

    enum CommitteeRequestType {
        None,
        Claim,  // #1
        ChangePoolManager,  // #2
        AddToCommittee,  // #3
        RemoveFromCommittee,  // #4
        ChangeCommitteeThreshold  // #5
    }

    struct CommitteeRequest {
        uint256 time;
        uint256 vote;
        bool executed;
        CommitteeRequestType operation;
        bytes data;
    }

    CommitteeRequest[] public committeeRequestArray;

    // Vote.
    mapping(address => mapping(uint256 => bool)) public committeeVote;

    // Access control.

    address public poolManager;

    mapping(address => uint256) public committeeIndexPlusOne;
    address[] public committeeArray;
    uint256 public committeeThreshold;

    // Event aggregator.
    address public eventAggregator;

    // This is a storage gap in case more state variables will be added
    // in the future.
    uint256[49] __gap;
}
