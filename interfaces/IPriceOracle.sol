// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

interface IPriceOracle {
    function collatPrice() external view returns (uint256);

    function ousdPrice() external view returns (uint256);

    function oruPrice() external view returns (uint256);
}
