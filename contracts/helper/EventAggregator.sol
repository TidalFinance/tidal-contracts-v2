// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../interface/IEventAggregator.sol";

contract EventAggregator is IEventAggregator, Initializable, OwnableUpgradeable {

    mapping(address => bool) public poolMap;

    // No additional state variables should be added here.
    // We may upgrade this file but only to add events.

    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __Ownable_init();
    }

    event SetEventAggregator(
        address indexed pool_,
        address oldAggregator_,
        address newAggregator_
    );

    event EnablePool(
        address indexed pool_,
        bool enabled_
    );

    // Events.
    event Buy(
        address indexed pool_,
        address indexed who_,
        uint256 indexed policyIndex_,
        uint256 amount_,
        uint256 fromWeek_,
        uint256 toWeek_,
        string notes_
    );

    event Deposit(
        address indexed pool_,
        address indexed who_,
        uint256 amount_
    );

    event Withdraw(
        address indexed pool_,
        address indexed who_,
        uint256 indexed requestIndex_,
        uint256 share_
    );

    event WithdrawPending(
        address indexed pool_,
        address indexed who_,
        uint256 indexed requestIndex_
    );

    event WithdrawReady(
        address indexed pool_,
        address indexed who_,
        uint256 indexed requestIndex_,
        bool succeeded_
    );

    // At most 3 indexed arguments is allowed by solidity
    event Refund(
        address indexed pool_,
        uint256 indexed policyIndex_,
        uint256 indexed week_,
        address who_,
        uint256 amount_
    );

    event Claim(
        address indexed pool_,
        uint256 policyIndex_,
        uint256 amount_,
        address receipient_
    );

    event ChangePoolManager(
        address indexed pool_,
        address poolManager_
    );

    event AddToCommittee(
        address indexed pool_,
        address who_
    );

    event RemoveFromCommittee(
        address indexed pool_,
        address who_
    );

    event ChangeCommitteeThreshold(
        address indexed pool_,
        uint256 threshold_
    );

    event VoteAndSupport(
        address indexed pool_,
        uint256 indexed requestIndex_
    );

    event Execute(
        address indexed pool_,
        uint256 indexed requestIndex_,
        uint256 operation_,
        bytes data_
    );

    function setPool(address pool_, bool on_) external onlyOwner {
        poolMap[pool_] = on_;
    }

    modifier onlyPool() {
        require(poolMap[msg.sender], "Only pool");
        _;
    } 

    function setEventAggregator(
        address oldAggregator_,
        address newAggregator_
    ) external onlyPool {
        emit SetEventAggregator(
            msg.sender,
            oldAggregator_,
            newAggregator_
        );
    }

    function enablePool(
        bool enabled_
    ) external onlyPool {
        emit EnablePool(
            msg.sender,
            enabled_
        );
    }

    function buy(
        address who_,
        uint256 policyIndex_,
        uint256 amount_,
        uint256 fromWeek_,
        uint256 toWeek_,
        string calldata notes_
    ) external onlyPool {
        emit Buy(
            msg.sender,
            who_,
            policyIndex_,
            amount_,
            fromWeek_,
            toWeek_,
            notes_
        );
    }

    function deposit(
        address who_,
        uint256 amount_
    ) external onlyPool {
        emit Deposit(
            msg.sender,
            who_,
            amount_
        );
    }

    function withdraw(
        address who_,
        uint256 requestIndex_,
        uint256 share_
    ) external onlyPool {
        emit Withdraw(
            msg.sender,
            who_,
            requestIndex_,
            share_
        );
    }

    function withdrawPending(
        address who_,
        uint256 requestIndex_
    ) external onlyPool {
        emit WithdrawPending(
            msg.sender,
            who_,
            requestIndex_
        );
    }

    function withdrawReady(
        address who_,
        uint256 requestIndex_,
        bool succeeded_
    ) external onlyPool {
        emit WithdrawReady(
            msg.sender,
            who_,
            requestIndex_,
            succeeded_
        );
    }

    function refund(
        uint256 policyIndex_,
        uint256 week_,
        address who_,
        uint256 amount_
    ) external onlyPool {
        emit Refund(
            msg.sender,
            policyIndex_,
            week_,
            who_,
            amount_
        );
    }

    function claim(
        uint256 policyIndex_,
        uint256 amount_,
        address receipient_
    ) external onlyPool {
        emit Claim(
            msg.sender,
            policyIndex_,
            amount_,
            receipient_
        );
    }

    function changePoolManager(
        address poolManager_
    ) external onlyPool {
        emit ChangePoolManager(
            msg.sender,
            poolManager_
        );
    }

    function addToCommittee(address who_) external onlyPool {
        emit AddToCommittee(
            msg.sender,
            who_
        );
    }

    function removeFromCommittee(address who_) external onlyPool {
        emit RemoveFromCommittee(
            msg.sender,
            who_
        );
    }

    function changeCommitteeThreshold(uint256 threshold_) external onlyPool {
        emit ChangeCommitteeThreshold(
            msg.sender,
            threshold_
        );
    }

    function voteAndSupport(
        uint256 requestIndex_
    ) external onlyPool {
        emit VoteAndSupport(
            msg.sender,
            requestIndex_
        );
    }

    function execute(
        uint256 requestIndex_,
        uint256 operation_,
        bytes calldata data_
    ) external onlyPool {
        emit Execute(
            msg.sender,
            requestIndex_,
            operation_,
            data_
        );
    }
}
