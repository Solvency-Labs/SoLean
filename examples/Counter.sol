// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

contract Counter {
    uint256 public x;

    function inc(uint256 amount) public {
        require(amount > 0);
        x += amount;
        assert(x >= amount);
    }
}
