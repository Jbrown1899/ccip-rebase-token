//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

contract Vault {
    IRebaseToken private immutable i_rebaseToken;

    event Deposit(address indexed user, uint256 amount);
    event Redeem(address indexed user, uint256 amount);

    error Vault__RedeemFailed();

    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    receive() external payable {} // fallback function to accept ETH deposits


    /**
     * @notice Allows users to deposit ETH into the vault
     * @dev Mints RebaseTokens equivalent to the deposited ETH
     */
    function deposit() external payable {
        // Logic to handle deposits into the vault
        i_rebaseToken.mint(msg.sender, msg.value); // Mint RebaseTokens equivalent to the deposited ETH
        emit Deposit(msg.sender, msg.value);
    }
    /**
     * @notice Allows users to redeem their RebaseTokens for ETH
     * @dev Burns RebaseTokens equivalent to the redeemed amount
     * @param _amount The amount of RebaseTokens to redeem
     */
    function redeem(uint256 _amount) external {
        if(_amount == type(uint256).max) {
            _amount = i_rebaseToken.balanceOf(msg.sender); // If amount is max, burn all tokens
        }
        
        // Logic to handle redemptions from the vault
        require(_amount > 0, "Amount must be greater than zero");
        i_rebaseToken.burn(msg.sender, _amount); // Burn RebaseTokens equivalent to the redeemed amount
        (bool success, ) = payable(msg.sender).call{value: _amount}(""); // Transfer ETH back to the user
        if (!success) {
            revert Vault__RedeemFailed();
        }
        emit Redeem(msg.sender, _amount);
    }

    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }
}