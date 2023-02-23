// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./../model/PoolModel.sol";

contract PoolProxy is PoolModel, Ownable {

    address public pool;

    function setPool(address pool_) public onlyOwner {
        pool = pool_;
    }

    constructor(address baseToken_, address tidalToken_) public {
        baseToken = baseToken_;
        tidalToken = tidalToken_;
        isTest = false;
    }

    fallback() external {
        address _impl = pool;
        require(_impl != address(0));

        assembly {
            let ptr := mload(0x40)
            calldatacopy(ptr, 0, calldatasize())
            let result := delegatecall(gas(), _impl, ptr, calldatasize(), 0, 0)
            let size := returndatasize()
            returndatacopy(ptr, 0, size)

            switch result
            case 0 {revert(ptr, size)}
            default {return (ptr, size)}
        }
    }
}
