// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

contract NonReentrancy {

    uint256 private islocked;

    modifier noReenter() {
        require(islocked == 0, 'Tidal: LOCKED');
        islocked = 1;
        _;
        islocked = 0;
    }
}
