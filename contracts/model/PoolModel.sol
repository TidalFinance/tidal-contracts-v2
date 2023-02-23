// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

contract PoolModel {
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

    // Vote.
    mapping(address => mapping(uint256 => bool)) committeeVote;

    // Access control.

    address public admin;

    mapping(address => uint256) public committeeIndexPlusOne;
    address[] public committeeArray;
    uint256 public committeeThreshold = 2;

    // Time control.

    uint256 public offset = 4 days;
    uint256 public timeExtra;
}
