// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

interface ISwapController {
    function swapUsdcToOusd(uint256 _amount, uint256 _minOut) external;

    function swapUsdcToOru(uint256 _amount, uint256 _minOut) external;

    function swapOruToUsdc(uint256 _amount, uint256 _minOut) external;

    function swapOusdToUsdc(uint256 _amount, uint256 _minOut) external;

    function zapInOru(
        uint256 _amount,
        uint256 _minUsdc,
        uint256 _minLp
    ) external returns (uint256);

    function zapInUsdc(
        uint256 _amount,
        uint256 _minOru,
        uint256 _minLp
    ) external returns (uint256);

    function zapOutOru(uint256 _amount, uint256 _minOut)
        external
        returns (uint256);

    function swapWAstrToUsdc(uint256 _amount, uint256 _minOut) external;
}
