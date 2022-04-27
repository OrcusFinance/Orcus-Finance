// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Airdrop is Ownable {
    /// @notice On contract deployment
    constructor() {
    }

    /**
     * @dev Airdrop function from external wallet to recipients.
     * @param from - Admin wallet
     * @param token - ERC20 address
     * @param amounts - amount of token to be sent
     * @param recipients - array of airdrop recipients
     */
    function airdrop(
        address from,
        address token,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external onlyOwner {
        require(from != address(0), "from address is zero");
        require(token != address(0), "tokenaddress is zero");
        require(amounts.length == recipients.length, "Wrong input arrays");
        require(recipients.length > 0, "empty arrays");
        for (uint256 i = 0; i < recipients.length; i++) {
            IERC20(token).transferFrom(from, recipients[i], amounts[i]);
        }
    }
}
