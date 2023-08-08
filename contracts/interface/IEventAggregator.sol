// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IEventAggregator {

    function setEventAggregator(
        address oldAggregator_,
        address newAggregator_
    ) external;

    function enablePool(
        bool enabled_
    ) external;

    function buy(
        address who_,
        uint256 policyIndex_,
        uint256 amount_,
        uint256 fromWeek_,
        uint256 toWeek_,
        string calldata notes_
    ) external;

    function deposit(
        address who_,
        uint256 amount_
    ) external;

    function withdraw(
        address who_,
        uint256 requestIndex_,
        uint256 share_
    ) external;

    function withdrawPending(
        address who_,
        uint256 requestIndex_
    ) external;

    function withdrawReady(
        address who_,
        uint256 requestIndex_,
        bool succeeded_
    ) external;

    function addPremium(
        uint256 policyIndex_,
        uint256 week_,
        uint256 amountPerShareOld_,
        uint256 amountPerShareDelta_
    ) external;

    function refund(
        uint256 policyIndex_,
        uint256 week_,
        address who_,
        uint256 amount_
    ) external;

    function addTidal(
        uint256 week_,
        uint256 accTidalPerShareOld_,
        uint256 accTidalPerShareDelta_
    ) external;

    function claim(
        uint256 requestIndex_,
        uint256 policyIndex_,
        uint256 amount_,
        address receipient_
    ) external;

    function changePoolManager(
        uint256 requestIndex_,
        address poolManager_
    ) external;

    function addToCommittee(
        uint256 requestIndex_,
        address who_
    ) external;

    function removeFromCommittee(
        uint256 requestIndex_,
        address who_
    ) external;

    function changeCommitteeThreshold(
        uint256 requestIndex_,
        uint256 threshold_
    ) external;

    function voteAndSupport(
        uint256 requestIndex_
    ) external;

    function execute(
        uint256 requestIndex_,
        uint256 operation_,
        bytes calldata data_
    ) external;
}
