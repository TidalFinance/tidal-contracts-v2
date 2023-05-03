# Tidal Contracts V2

The two smart contracts that matters are

`contracts/Pool.sol`
and
`contracts/helper/EventAggregator.sol`

# 1. Pool Manager and Committee

Every Pool is a standalone smart contract. It is made upgradeable with OpenZeppelin’s Proxy Upgrade Pattern.

When the Pool was initialized, pool manager and committee members are assigned.

Pool manager can:

- Enable or disable the pool in emergency
- Configure pool parameters
- Add new policies or edit existing policies
- Propose for a payout, or claim (by specifying amount and payment address)

Committee members can:

- Vote for a payout request
- Propose and vote to change the pool manager
- Propose and vote to change committee members
- Propose and vote to change the voting threshold

Once a proposal received enough approving votes, then it can be executed.

# 2. Sellers and Buyers

A random user can become a seller (or shareholder) of the pool by depositing base tokens (usually USCD or ETH) to the pool.

User can also become buyers, by calling the “buy” function, and purchasing from one of the policies of the pool for a few weeks.

Buyers’ money go to the pockets of the sellers in the form of premium, every week. However, when accidents happen, sellers’ shares in the pool decrease in value, and buyers get payouts from the pool.

Seller can withdraw from the pool, but the process takes time. After calling “withdraw”, the user needs to wait for withdrawWaitWeeks1 (usually 10 weeks), to call “withdrawPending”. And wait additional withdrawWaitWeeks2 (usually 1 week), to call “withdrawReady”.

In practice, both of the “withdrawPending” and the “withdrawReady” will be triggered by a script automatically, and users don’t need to worry about it.

After “withdrawPending” is called, the corresponding capacity is deducted from the pool, but only after “withdrawReady” the assets go to the users’ wallet. The mechanism is for covering the gap when payout happens.

# 3. Cron Jobs Called by Scripts

The following functions, addPremium, refund, and addTidal, should be triggered by a script every Sunday for every pool.

”addPremium” collects premium paid by the buyers.
”refund” potentially returns overpaid premium back to the buyers, in case the capacity of the pool is below the subscribed amount from the buyers (it happens in the case of a payout).

“addTidal” is for pool manager adding additional rewards for the sellers.

# 4. Deployment

And there will be multiple proxies and one implementation of the Pools, and one proxy and one implementation of EventAggregator.

Every Pool will be configed differently depending on the Pool admin's requirement.

Whenever a new Pool is needed, just deploy a new proxy of the Pool.

We use "EventAggregator" to aggregate all the events from all Pools.
