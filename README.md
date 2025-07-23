# Cross-chain rebase token from cyfrin updraft

1. A protocol that allows uiser to deposit into a vault and in return, receive rebase tokens that represent their underlying balance
2. Rebase token -> balanceOf function is dynamic to show the changing balance with time.
   - Balance increases linearly with time
   - mint tokens to users everytime they preform and action: minting, burning, transferring, or bridging
3. Interest rate
   - Individually set and interest rate or each user based on some global interest rate of the protocol at the time the user deposits into the vault
   - This global interest rate can only decrease to incentivise/reward early adopters.
 - 