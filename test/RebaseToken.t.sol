//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";


contract RebaseTokenTest is Test {
    uint256 private constant PRECISION_FACTOR = 1e18; // Used to handle fixed-point calculations
    
    RebaseToken private rebaseToken;
    Vault private vault;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    function setUp() public {
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        (bool success,) = payable(address(vault)).call{value: 1 ether}(""); // Deposit 1 ether into the vault
        vm.stopPrank();
    }

    /**
     * @param rewardAmount the amount of rewards to add to the vault
     * @notice This function allows the owner to add rewards to the vault to ensure test completes
     */
    function addRewardsToVault(uint256 rewardAmount) public {
        (bool success,) = payable(address(vault)).call{value: rewardAmount}(""); // Add rewards to the vault
        require(success, "Failed to add rewards to vault");
    }

    function testDepositLinear(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max); // Ensure amount is within a reasonable range
        vm.startPrank(user);
        vm.deal(user, amount); // Give user the specified amount
        vault.deposit{value: amount}(); // User deposits into the vault
        //check balance
        uint256 startBalance = rebaseToken.balanceOf(user);
        console.log("starting balance: ", startBalance);
        assertEq(startBalance, amount);
        //warp the time and check balance
        vm.warp(block.timestamp + 1 hours); // Warp time by 1 hour
        uint256 middleBalance = rebaseToken.balanceOf(user);
        assertGt(middleBalance, startBalance);
        //warp time again and check balance
        vm.warp(block.timestamp + 1 hours); // Warp time by 1 hour
        uint256 endBalance = rebaseToken.balanceOf(user);
        assertGt(endBalance, middleBalance);

        //check that the increase between the two hours is the same
        uint256 firstHourIncrease = middleBalance - startBalance;
        uint256 secondHourIncrease = endBalance - middleBalance;
        assertApproxEqAbs(firstHourIncrease, secondHourIncrease, 1);

        vm.stopPrank();
    }

    function testRedeemStraightAway(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max); // Ensure amount is within a reasonable range
        vm.startPrank(user);
        vm.deal(user, amount); // Give user the specified amount
        vault.deposit{value: amount}(); // User deposits into the vault
        //check balance
        uint256 startBalance = rebaseToken.balanceOf(user);
        console.log("starting balance: ", startBalance);
        assertEq(startBalance, amount);
        //redeem straight away
        vault.redeem(type(uint256).max); // Redeem all tokens
        uint256 endBalance = rebaseToken.balanceOf(user);
        assertEq(endBalance, 0);
        assertEq(address(user).balance, amount); // User should have received the full amount back in ETH
        vm.stopPrank();
    }

    function testRedeemAfterTimeWarp(uint256 depositAmount, uint256 time) public {
        time = bound(time, 1000, type(uint96).max); // Ensure time is within a reasonable range
        depositAmount = bound(depositAmount, 1e5, type(uint96).max); // Ensure amount is within a reasonable range
        
        vm.deal(user, depositAmount); // Give user the specified amount
        vm.prank(user);
        vault.deposit{value: depositAmount}(); // User deposits into the vault
        
        //warp the time and check balance
        vm.warp(block.timestamp + time); // Warp time by the specified amount
        uint256 balanceAfter = rebaseToken.balanceOf(user);

        vm.deal(owner, balanceAfter - depositAmount);
        vm.prank(owner);
        addRewardsToVault(balanceAfter - depositAmount); // Add rewards to the vault to ensure test completes

        //redeem straight away
        vm.prank(user);
        vault.redeem(type(uint256).max); // Redeem all tokens

        uint256 endBalance = address(user).balance;
        assertEq(endBalance, balanceAfter);
        assertGt(endBalance, depositAmount); // User should have more than the initial deposit due to interest
    }

    function testTransfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 1e5 + 1e5, type(uint96).max); // Ensure amount is within a reasonable range
        amountToSend = bound(amountToSend, 1e5, amount - 1e5); // Ensure amount to send is within a reasonable range
    
        //deposit
        vm.deal(user, amount); // Give user the specified amount
        vm.prank(user);
        vault.deposit{value: amount}(); // User deposits into the vault

        address user2 = makeAddr("user2");
        uint256 userBalance = rebaseToken.balanceOf(user);
        uint256 user2Balance = rebaseToken.balanceOf(user2);
        assertEq(userBalance, amount);
        assertEq(user2Balance, 0);

        //owner reduces the interest rate
        vm.prank(owner);
        rebaseToken.setInterestRate(4e10); 

        //transfer
        vm.prank(user);
        rebaseToken.transfer(user2, amountToSend); // User transfers tokens to user2
        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        uint256 user2BalanceAfterTransfer = rebaseToken.balanceOf(user2);
        assertEq(userBalanceAfterTransfer, userBalance - amountToSend);
        assertEq(user2BalanceAfterTransfer, amountToSend);

        //check the user interest rates to ensure they are inherited correctly
        uint256 userInterestRate = rebaseToken.getUserInterestRate(user);
        uint256 user2InterestRate = rebaseToken.getUserInterestRate(user2);
        assertEq(userInterestRate, 5e10); // User's interest rate should be
        assertEq(user2InterestRate, 5e10); // User2's interest rate should be the same as User's
    }

    function testCannotSetInterestRateIfNotOwner(uint256 newInterestRate, address userX) public {
        vm.assume(userX != owner);
        newInterestRate = bound(newInterestRate, 1, 10e10); // Ensure new interest rate is within a reasonable range
        vm.prank(userX); // Non-owner tries to set interest rate
        vm.expectPartialRevert(Ownable.OwnableUnauthorizedAccount.selector);
        rebaseToken.setInterestRate(newInterestRate); // Non-owner tries to set interest rate
    }

    function testCannotCallMintAndBurn() public {
        vm.prank(user);
        vm.expectPartialRevert(bytes4(IAccessControl.AccessControlUnauthorizedAccount.selector));
        rebaseToken.mint(user, 100); // Non-role user tries to mint tokens
        vm.expectPartialRevert(bytes4(IAccessControl.AccessControlUnauthorizedAccount.selector));
        rebaseToken.burn(user, 100); // Non-role user tries to burn tokens
    }

    function testGetPrincipalAmount(uint256 amount) public {
        uint256 principalAmount = bound(amount, 1e5, type(uint96).max); // Ensure amount is within a reasonable range
        vm.deal(user, principalAmount); // Give user the specified amount
        vm.prank(user);
        vault.deposit{value: principalAmount}(); // User deposits into the vault
        uint256 principalBalance = rebaseToken.principleBalanceOf(user);
        assertEq(principalBalance, principalAmount); // Principal balance should match the deposited amount
    
        //warp the time and check principal balance
        vm.warp(block.timestamp + 1 hours); // Warp time by 1 hour
        uint256 principalBalanceAfter = rebaseToken.principleBalanceOf(user);
        assertEq(principalBalanceAfter, principalAmount); // Principal balance should still match the deposited amount
    }

    function testGetRebaseTokenAddress() public {
        address rebaseTokenAddress = vault.getRebaseTokenAddress();
        assertEq(rebaseTokenAddress, address(rebaseToken)); // Ensure the address returned by the vault matches the RebaseToken address
    }

    function testInterestRateCanOnlyDecrease(uint256 newInterestRate) public {
        uint256 initialInterestRate = rebaseToken.getInterestRate();
        newInterestRate = bound(newInterestRate, initialInterestRate, type(uint96).max); // Ensure new interest rate is within a reasonable range
        vm.prank(owner);
        vm.expectPartialRevert(bytes4(RebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector));
        rebaseToken.setInterestRate(newInterestRate); // Owner sets a new interest rate
        assertEq(rebaseToken.getInterestRate(), initialInterestRate); // Interest rate should not change
    }
}