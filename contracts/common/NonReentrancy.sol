// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

contract NonReentrancy {

    uint256 private islocked;

    // No additional state variables should be added here.
    // We won't upgrade this file.

    modifier noReenter() {
        require(islocked == 0, 'Tidal: LOCKED');
        islocked = 1;
        _;
        islocked = 0;
    }

    modifier noReenterView() {
        require(islocked == 0, 'Tidal: LOCKED');
        _;
    }
}
