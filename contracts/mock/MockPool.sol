// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";

import "../Pool.sol";

contract MockPool is Pool {

    constructor(address baseToken_, address tidalToken_) public {
        baseToken = baseToken_;
        tidalToken = tidalToken_;
        isTest = true;
    }
}
