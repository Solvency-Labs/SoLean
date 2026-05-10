// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract SimpleVault {
    uint256 public totalAssets;
    uint256 public totalShares;

    function deposit(uint256 assets) public {
        require(assets > 0);
        totalAssets += assets;
        totalShares += assets;
        assert(totalAssets >= totalShares);
    }

    function withdraw(uint256 shares) public {
        require(shares > 0);
        require(totalShares >= shares);
        require(totalAssets >= shares);
        totalAssets -= shares;
        totalShares -= shares;
        assert(totalAssets >= totalShares);
    }
}
