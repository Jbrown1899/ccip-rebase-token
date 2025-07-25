// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;


import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title RebaseToken
 * @author Jbrown
 * @notice A cross chain rebase token that incentivises users to deposit into a vault
 * @notice The interest rate in the smart contract can only decrease
 * @notice Each user will have their own interest rate that is the global interest rate at time of deposit
 * 
 */




contract RebaseToken is ERC20, Ownable, AccessControl {
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 currentInterestRate, uint256 newInterestRate);
    
    uint256 private constant PRECISION_FACTOR = 1e18; // Used to handle fixed-point calculations
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");
    
    uint256 private s_interestRate = 5e10; //rate per second, e.g. 5e10 = 0.05% per second (in basis points)
    mapping (address => uint256) private s_userInterestRate;
    mapping (address => uint256) private s_userLastUpdatedTimestamp;
    
    event InterestRateSet(uint256 newInterestRate);

    constructor() ERC20("RebaseToken", "RBST") Ownable(msg.sender){}

    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    /**
     * 
     * @param _newInterestRate the new interest rate to set
     * @notice This function allows the owner to set a new interest rate
     * @notice The new interest rate must be less than the current interest rate
     * @notice Only the owner can call this function
     */
    
    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        require(_newInterestRate < s_interestRate, RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate));
        s_interestRate = _newInterestRate;
        emit InterestRateSet(_newInterestRate);
    }

    function principleBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user); // Returns the user's balance without accrued interest
    }

    /**
     * 
     * @param _to the address to mint tokens to
     * @notice This function mints tokens to a user and sets their interest rate to the current global interest rate
     * @notice It also mints any accrued interest to the user before minting the new tokens
     * @param _amount the amount of tokens to mint
     */

    function mint(address _to, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = s_interestRate; // Set the user's interest rate to the current global interest rate
        _mint(_to, _amount); //inherited from openzeppelin ERC20
    }

    /**
     * @notice Burns a specific amount of tokens from a user
     * @param _from the address to burn from
     * @param _amount the amount to burn
     */

    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_from);
        _burn(_from, _amount); //inherited from openzeppelin ERC20
    }

    function balanceOf(address _user) public view override returns (uint256) { 
        // shares * current accumulated interest for that user since their interest was last minted to them.
        return (super.balanceOf(_user) * _calculateUserAccumulatedInterestSinceLastUpdate(_user)) / PRECISION_FACTOR;
    }

    /**
     * @notice This function transfers tokens from the sender to the recipient
     * @param _recipient the address to transfer tokens to
     * @param _amount the amount of tokens to transfer
     * @notice Returns true if the transfer was successful
     */
    
    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender); // If amount is max, transfer all tokens
        }
        if(balanceOf(_recipient) == 0){
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender]; // Set the recipient's interest rate to the sender's interest rate
        }
        return super.transfer(_recipient, _amount);
    }

    /**
     * @notice This function transfers tokens from the sender to the recipient
     * @param _sender the address to transfer tokens from
     * @param _recipient the address to transfer tokens to
     * @param _amount the amount of tokens to transfer
     * @notice Returns true if the transfer was successful
     */

    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool){
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_sender); // If amount is max, transfer all tokens
        }
        if(balanceOf(_recipient) == 0){
            s_userInterestRate[_recipient] = s_userInterestRate[_sender]; // Set the recipient's interest rate to the sender's interest rate
        }
        return super.transferFrom(_sender, _recipient, _amount);
    }

    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user) internal view returns (uint256) {
        //linear interest calculation
        uint256 lastUpdatedTimestamp = s_userLastUpdatedTimestamp[_user];
        if (lastUpdatedTimestamp == 0) {
            return 0; // No interest accrued if never updated
        }
        uint256 timeElapsed = block.timestamp - lastUpdatedTimestamp;
        uint256 userInterestRate = s_userInterestRate[_user];
        return 1 * PRECISION_FACTOR + (userInterestRate * timeElapsed);
    }

    /**
     * 
     * @param _user the user to mint accrued interest for
     * @notice This function mints the accrued interest for a user based on their last updated timestamp
     * @notice It calculates the difference between the current balance and the previous balance
     * @notice and mints that difference as interest to the user
     */
    
    function _mintAccruedInterest(address _user) internal {
        // (1) find current balance of rebase tokens
        // (2) find current balance including and interest via balanceOf(user)
        uint256 previousPrincipleBalance = super.balanceOf(_user);
        uint256 newBalance = balanceOf(_user);

        s_userLastUpdatedTimestamp[_user] = block.timestamp; // Update the last updated timestamp for the user
        if (newBalance > previousPrincipleBalance) {
            // Mint the difference as interest
            _mint(_user, newBalance - previousPrincipleBalance);
        }
    }

    /**
     * * @notice This function returns the current interest rate
     */
    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }

    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }
}