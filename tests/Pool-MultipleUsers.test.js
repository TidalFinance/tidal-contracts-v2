const { expectRevert, time } = require('@openzeppelin/test-helpers');
const ethers = require('ethers');

const Pool = artifacts.require('Pool');
const MockERC20 = artifacts.require('MockERC20');

const decToHex = (x, decimal=18) => {
    if (x == 0) return '0x0';
    let str = x;
    for (var index = 0; index < decimal; index++) {
      str += "0";
    }

    let pos = str.indexOf(".");
    if (pos != -1) {
      str = str.substr(0, pos) + str.substr(pos + 1, decimal);
    }

    var dec = str.toString().split(''), sum = [], hex = [], i, s
    while (dec.length) {
      s = 1 * parseInt(dec.shift())
      for (i = 0; s || i < sum.length; i++) {
        s += (sum[i] || 0) * 10
        sum[i] = s % 16
        s = (s - sum[i]) / 16
      }
    }

    while (sum.length) {
      hex.push(sum.pop().toString(16));
    }

    return '0x' + hex.join('');
}

contract('Pool', ([
        owner, poolManager, seller0, seller1, seller2, buyer0, buyer1, anyone,
        voter0, voter1]) => {

    beforeEach(async () => {
        this.USDC = await MockERC20.new(
            "USDC", "USDC", decToHex(502000), {from: owner});
        this.Tidal = await MockERC20.new(
            "Tidal", "TIDAL", decToHex(1000000), {from: owner});
        await this.USDC.transfer(seller0, decToHex(10000), {from: owner});
        await this.USDC.transfer(seller1, decToHex(20000), {from: owner});
        await this.USDC.transfer(seller2, decToHex(10000), {from: owner});
        await this.USDC.transfer(buyer0, decToHex(10000), {from: owner});
        await this.USDC.transfer(buyer1, decToHex(20000), {from: owner});

        this.Pool = await Pool.new({from: owner});
        await this.Pool.initialize(
            this.USDC.address, this.Tidal.address, true,
            poolManager, [voter0, voter1], {from: owner});

        await this.Pool.setPool(
            10,
            1,
            10,
            20000, // 2% withdrawFee
            50000, // 5% managementFee1
            30000,  // 3% managementFee2
            1,
            "",
            "",
            {from: poolManager}
        );

        // Adds policy.
        await this.Pool.addPolicy(500000, 10000, "Metamask", "Bla bla", {from: poolManager});

        // Defines minimum floating-point calculation error.
        this.MIN_ERROR = 0.0005e18; // 0.0005 USDC
    });

    it('should work', async () => {
        const currentWeek = +(await this.Pool.getCurrentWeek()).valueOf();

        // In week0, seller0 deposits 10,000 USDC.
        await this.USDC.approve(
            this.Pool.address, decToHex(10000), {from: seller0});
        await this.Pool.deposit(decToHex(10000), {from: seller0});

        // Buyer0 buys 10,000 USDC worth of Metamask policy, from Sunday,
        // for 10 weeks.
        // It should cost 100 USDC per week, totally 1000 USDC for 10 weeks.
        await this.USDC.approve(
            this.Pool.address, decToHex(1000), {from: buyer0});
        await this.Pool.buy(
            0,
            decToHex(10000),
            currentWeek + 1,
            currentWeek + 11,
            "notes",
            {from: buyer0}
        );

        // *** Move to week1.
        await this.Pool.setTimeExtra(3600 * 24 * 7);
        await this.Pool.addPremium(0, {from: anyone});

        // So far there should be 100 USDC premium.
        // 92% of it, or 92 goes to seller0
        // 5% of it, or 5 goes to managementFee1
        // 3% of it, or 3 goes to managementFee2
        const base0AtWeek1 =
            +(await this.Pool.getUserBaseAmount(seller0)).valueOf();
        assert.isTrue(Math.abs(base0AtWeek1 - 10092e18) < this.MIN_ERROR);

        // Capacity should be (10092 + 5) / 50% - 10000 = 10194
        const capacityAtWeek1 =
            +(await this.Pool.getCurrentAvailableCapacity(0)).valueOf();
        assert.isTrue(Math.abs(capacityAtWeek1 - 10194e18) <
            this.MIN_ERROR);

        // *** Move to week2.
        await this.Pool.setTimeExtra(3600 * 24 * 14);
        await this.Pool.addPremium(0, {from: anyone});

        // seller1 now deposits 30000 USDC.
        await this.USDC.approve(
            this.Pool.address, decToHex(20000), {from: seller1});
        await this.Pool.deposit(decToHex(20000), {from: seller1});

        // Another 100 USDC premium.
        // 92% of it, or 92 goes to seller0 & managementFee1 with ratio 10092:5
        // 5% of it, or 5 goes to managementFee1
        // 3% of it, or 3 goes to managementFee2
        // Seller0 should have 10000 + 92 + 92 * 10092 / 10097 = 10183.9544
        const base0AtWeek2 =
            +(await this.Pool.getUserBaseAmount(seller0)).valueOf();
        assert.isTrue(Math.abs(base0AtWeek2 - 10183.9544e18) < this.MIN_ERROR);

        // Capacity should be 50388
        const capacityAtWeek2 =
            +(await this.Pool.getCurrentAvailableCapacity(0)).valueOf();
        assert.isTrue(Math.abs(capacityAtWeek2 - 50388e18) <
            this.MIN_ERROR);

        // *** Move to week3.
        await this.Pool.setTimeExtra(3600 * 24 * 21);
        await this.Pool.addPremium(0, {from: anyone});

        // ### Add 10000 Tidal as bonus
        await this.Tidal.approve(
            this.Pool.address, decToHex(10000), {from: owner});
        await this.Pool.addTidal(decToHex(10000), {from: owner});

        // Buyer1 buys 20,000 USDC worth of Metamask policy, from Sunday,
        // for 9 weeks.
        // It should cost 200 USDC per week, totally 1800 USDC for 9 weeks.
        await this.USDC.approve(
            this.Pool.address, decToHex(1800), {from: buyer1});
        await this.Pool.buy(
            0,
            decToHex(20000),
            currentWeek + 4,
            currentWeek + 13,
            "notes",
            {from: buyer1}
        );

        // seller0: 10214.9846
        // seller1: 20060.9393
        // poolManager: 15.0762
        const base0AtWeek3 =
            +(await this.Pool.getUserBaseAmount(seller0)).valueOf();
        assert.isTrue(Math.abs(base0AtWeek3 - 10214.9846e18) < this.MIN_ERROR);
        const base1AtWeek3 =
            +(await this.Pool.getUserBaseAmount(seller1)).valueOf();
        assert.isTrue(Math.abs(base1AtWeek3 - 20060.9393e18) < this.MIN_ERROR);
        const baseAdminAtWeek3 =
            +(await this.Pool.getUserBaseAmount(poolManager)).valueOf();
        assert.isTrue(Math.abs(baseAdminAtWeek3 - 15.0762e18) < this.MIN_ERROR);

        // seller0 tidal: 10000 * 10214.9846 / (10214.9846 + 20060.9393 + 15.0762) = 3372.2837
        // seller1 tidal: 10000 * 20060.9393 / (10214.9846 + 20060.9393 + 15.0762) = 6622.73917
        // poolManager tidal: 10000 * 15.0762 / (10214.9846 + 20060.9393 + 15.0762) = 4.9771219
        const tidal0AtWeek3 =
            +(await this.Pool.getUserTidalAmount(seller0)).valueOf();
        assert.isTrue(Math.abs(tidal0AtWeek3 - 3372.2837e18) < this.MIN_ERROR);
        const tidal1AtWeek3 =
            +(await this.Pool.getUserTidalAmount(seller1)).valueOf();
        assert.isTrue(Math.abs(tidal1AtWeek3 - 6622.73917e18) < this.MIN_ERROR);
        const tidalAdminAtWeek3 =
            +(await this.Pool.getUserTidalAmount(poolManager)).valueOf();
        assert.isTrue(Math.abs(tidalAdminAtWeek3 - 4.9771219e18) < this.MIN_ERROR);

        // Capacity: 50582
        const capacityAtWeek3 =
            +(await this.Pool.getCurrentAvailableCapacity(0)).valueOf();
        assert.isTrue(Math.abs(capacityAtWeek3 - 50582e18) <
            this.MIN_ERROR);

        // *** Move to week4.
        await this.Pool.setTimeExtra(3600 * 24 * 28);
        await this.Pool.addPremium(0, {from: anyone});

        // seller0 now withdraws all USDC.
        const seller0InfoAtWeek4 = await this.Pool.userInfoMap(seller0, {from: anyone});
        await this.Pool.withdraw(decToHex(seller0InfoAtWeek4.share / 1e18), {from: seller0});

        // seller0: 10308.0596
        // seller1: 20243.7269
        const base0AtWeek4 =
            +(await this.Pool.getUserBaseAmount(seller0)).valueOf();
        assert.isTrue(Math.abs(base0AtWeek4 - 10308.0596e18) < this.MIN_ERROR);
        const base1AtWeek4 =
            +(await this.Pool.getUserBaseAmount(seller1)).valueOf();
        assert.isTrue(Math.abs(base1AtWeek4 - 20243.7269e18) < this.MIN_ERROR);

        // Capacity: 31164
        const capacityAtWeek4 =
            +(await this.Pool.getCurrentAvailableCapacity(0)).valueOf();
        assert.isTrue(Math.abs(capacityAtWeek4 - 31164e18) <
            this.MIN_ERROR);

        // *** Move to week5.
        await this.Pool.setTimeExtra(3600 * 24 * 35);
        await this.Pool.addPremium(0, {from: anyone});

        // seller0: 10401.0890
        // seller1: 20426.4248
        const base0AtWeek5 =
            +(await this.Pool.getUserBaseAmount(seller0)).valueOf();
        assert.isTrue(Math.abs(base0AtWeek5 - 10401.0890e18) < this.MIN_ERROR);
        const base1AtWeek5 =
            +(await this.Pool.getUserBaseAmount(seller1)).valueOf();
        assert.isTrue(Math.abs(base1AtWeek5 - 20426.4248e18) < this.MIN_ERROR);

        // Capacity: 31746
        const capacityAtWeek5 =
            +(await this.Pool.getCurrentAvailableCapacity(0)).valueOf();
        assert.isTrue(Math.abs(capacityAtWeek5 - 31746e18) <
            this.MIN_ERROR);

        // *** Move to week6.
        await this.Pool.setTimeExtra(3600 * 24 * 42);
        await this.Pool.addPremium(0, {from: anyone});

        // seller0: 10494.0732
        // seller1: 20609.0340
        // poolManager: 60.8928
        const base0AtWeek6 =
            +(await this.Pool.getUserBaseAmount(seller0)).valueOf();
        assert.isTrue(Math.abs(base0AtWeek6 - 10494.0732e18) < this.MIN_ERROR);
        const base1AtWeek6 =
            +(await this.Pool.getUserBaseAmount(seller1)).valueOf();
        assert.isTrue(Math.abs(base1AtWeek6 - 20609.0340e18) < this.MIN_ERROR);
        const baseAdminAtWeek6 =
            +(await this.Pool.getUserBaseAmount(poolManager)).valueOf();
        assert.isTrue(Math.abs(baseAdminAtWeek6 - 60.8928e18) < this.MIN_ERROR);

        const collateralAmountAtWeek6 = +(await this.Pool.getCollateralAmount()).valueOf();
        assert.isTrue(Math.abs(collateralAmountAtWeek6 - 31164.0000e18) < this.MIN_ERROR);

        // Payout of 20000
        await this.Pool.claim(0, decToHex(20000), owner, {from: poolManager});
        await this.Pool.vote(0, 1, {from: voter0});
        await this.Pool.vote(0, 1, {from: voter1});
        await this.Pool.execute(0, {from: anyone});

        // seller0 (after payout): 3759.3323
        // seller1 (after payout): 7382.8538
        // poolManager (after payout): 21.8139
        const base0AtWeek6P =
            +(await this.Pool.getUserBaseAmount(seller0)).valueOf();
        assert.isTrue(Math.abs(base0AtWeek6P - 3759.3323e18) < this.MIN_ERROR);
        const base1AtWeek6P =
            +(await this.Pool.getUserBaseAmount(seller1)).valueOf();
        assert.isTrue(Math.abs(base1AtWeek6P - 7382.8538e18) < this.MIN_ERROR);
        const baseAdminAtWeek6P =
            +(await this.Pool.getUserBaseAmount(poolManager)).valueOf();
        assert.isTrue(Math.abs(baseAdminAtWeek6P - 21.8139e18) < this.MIN_ERROR);

        const collateralAmountAtWeek6P = +(await this.Pool.getCollateralAmount()).valueOf();
        assert.isTrue(Math.abs(collateralAmountAtWeek6P - 11164.0000e18) < this.MIN_ERROR);

        // Capacity: 0
        const capacityAtWeek6 =
            +(await this.Pool.getCurrentAvailableCapacity(0)).valueOf();
        assert.isTrue(Math.abs(capacityAtWeek6 - 0) <
            this.MIN_ERROR);

        // *** Move to week7.
        await this.Pool.setTimeExtra(3600 * 24 * 49);
        await this.Pool.addPremium(0, {from: anyone});

        await this.Pool.refund(0, currentWeek + 7, buyer0, {from: anyone});
        await this.Pool.refund(0, currentWeek + 7, buyer1, {from: anyone});

        // seller1 withdraws 5000
        const poolInfoAtWeek7 = await this.Pool.poolInfo({from: anyone});
        const withdrawAmountAtWeek7 = 5000e18 / (+poolInfoAtWeek7.amountPerShare);
        await this.Pool.withdraw(decToHex(withdrawAmountAtWeek7), {from: seller1});

        // seller0: 3828.5040
        // seller1: 7518.6983
        // poolManager: 22.2153
        const base0AtWeek7 =
            +(await this.Pool.getUserBaseAmount(seller0)).valueOf();
        assert.isTrue(Math.abs(base0AtWeek7 - 3828.5040e18) < this.MIN_ERROR);
        const base1AtWeek7 =
            +(await this.Pool.getUserBaseAmount(seller1)).valueOf();
        assert.isTrue(Math.abs(base1AtWeek7 - 7518.6983e18) < this.MIN_ERROR);
        const baseAdminAtWeek7 =
            +(await this.Pool.getUserBaseAmount(poolManager)).valueOf();
        assert.isTrue(Math.abs(baseAdminAtWeek7 - 33.3793e18) < this.MIN_ERROR);

        const collateralAmountAtWeek7 = +(await this.Pool.getCollateralAmount()).valueOf();
        assert.isTrue(Math.abs(collateralAmountAtWeek7 - 11380.5816e18) < this.MIN_ERROR);

        // Capacity: 0
        const capacityAtWeek7 =
            +(await this.Pool.getCurrentAvailableCapacity(0)).valueOf();
        assert.isTrue(Math.abs(capacityAtWeek7 - 0) <
            this.MIN_ERROR);


        // *** Move to week8.
        await this.Pool.setTimeExtra(3600 * 24 * 56);
        await this.Pool.addPremium(0, {from: anyone});

        await this.Pool.refund(0, currentWeek + 8, buyer0, {from: anyone});
        await this.Pool.refund(0, currentWeek + 8, buyer1, {from: anyone});

        // seller0: 3898.9485
        // seller1: 7657.0423
        // poolManager: 45.3740
        const base0AtWeek8 =
            +(await this.Pool.getUserBaseAmount(seller0)).valueOf();
        assert.isTrue(Math.abs(base0AtWeek8 - 3898.9485e18) < this.MIN_ERROR);
        const base1AtWeek8 =
            +(await this.Pool.getUserBaseAmount(seller1)).valueOf();
        assert.isTrue(Math.abs(base1AtWeek8 - 7657.0423e18) < this.MIN_ERROR);
        const baseAdminAtWeek8 =
            +(await this.Pool.getUserBaseAmount(poolManager)).valueOf();
        assert.isTrue(Math.abs(baseAdminAtWeek8 - 45.3740e18) < this.MIN_ERROR);

        const collateralAmountAtWeek8 = +(await this.Pool.getCollateralAmount()).valueOf();
        assert.isTrue(Math.abs(collateralAmountAtWeek8 - 11601.3649e18) < this.MIN_ERROR);

        // Capacity: 0
        const capacityAtWeek8 =
            +(await this.Pool.getCurrentAvailableCapacity(0)).valueOf();
        assert.isTrue(Math.abs(capacityAtWeek8 - 0) <
            this.MIN_ERROR);

        // seller2 deposits 10000
        await this.USDC.approve(
            this.Pool.address, decToHex(10000), {from: seller2});
        await this.Pool.deposit(decToHex(10000), {from: seller2});

        // Capacity (after deposit): 13202.7298
        const capacityAtWeek8D =
            +(await this.Pool.getCurrentAvailableCapacity(0)).valueOf();
        assert.isTrue(Math.abs(capacityAtWeek8D - 13202.7298e18) <
            this.MIN_ERROR);

        // *** Move to week9.
        await this.Pool.setTimeExtra(3600 * 24 * 63);
        await this.Pool.addPremium(0, {from: anyone});

        // seller0: 3948.7653
        // seller1: 7754.8761
        // poolManager: 60.9538
        const base0AtWeek9 =
            +(await this.Pool.getUserBaseAmount(seller0)).valueOf();
        assert.isTrue(Math.abs(base0AtWeek9 - 3948.7653e18) < this.MIN_ERROR);
        const base1AtWeek9 =
            +(await this.Pool.getUserBaseAmount(seller1)).valueOf();
        assert.isTrue(Math.abs(base1AtWeek9 - 7754.8761e18) < this.MIN_ERROR);
        const baseAdminAtWeek9 =
            +(await this.Pool.getUserBaseAmount(poolManager)).valueOf();
        assert.isTrue(Math.abs(baseAdminAtWeek9 - 60.9538e18) < this.MIN_ERROR);

        const collateralAmountAtWeek9 = +(await this.Pool.getCollateralAmount()).valueOf();
        assert.isTrue(Math.abs(collateralAmountAtWeek9 - 21892.3649e18) < this.MIN_ERROR);

        // Capacity: 13784.7298
        const capacityAtWeek9 =
            +(await this.Pool.getCurrentAvailableCapacity(0)).valueOf();
        assert.isTrue(Math.abs(capacityAtWeek9 - 13784.7298e18) <
            this.MIN_ERROR);

        // *** Move to week10.
        await this.Pool.setTimeExtra(3600 * 24 * 70);
        await this.Pool.addPremium(0, {from: anyone});

        // seller0: 3998.5479
        // seller1: 7852.6429
        // poolManager: 76.7222
        const base0AtWeek10 =
            +(await this.Pool.getUserBaseAmount(seller0)).valueOf();
        assert.isTrue(Math.abs(base0AtWeek10 - 3998.5479e18) < this.MIN_ERROR);
        const base1AtWeek10 =
            +(await this.Pool.getUserBaseAmount(seller1)).valueOf();
        assert.isTrue(Math.abs(base1AtWeek10 - 7852.6429e18) < this.MIN_ERROR);
        const baseAdminAtWeek10 =
            +(await this.Pool.getUserBaseAmount(poolManager)).valueOf();
        assert.isTrue(Math.abs(baseAdminAtWeek10 - 76.7222e18) < this.MIN_ERROR);

        const collateralAmountAtWeek10 = +(await this.Pool.getCollateralAmount()).valueOf();
        assert.isTrue(Math.abs(collateralAmountAtWeek10 - 22183.3649e18) < this.MIN_ERROR);

        // Capacity: 14366.7298
        const capacityAtWeek10 =
            +(await this.Pool.getCurrentAvailableCapacity(0)).valueOf();
        assert.isTrue(Math.abs(capacityAtWeek10 - 14366.7298e18) <
            this.MIN_ERROR);

        // *** Move to week11.
        await this.Pool.setTimeExtra(3600 * 24 * 77);
        await this.Pool.addPremium(0, {from: anyone});

        // seller0: 4031.7139
        // seller1: 7917.7767
        // poolManager: 87.3586
        const base0AtWeek11 =
            +(await this.Pool.getUserBaseAmount(seller0)).valueOf();
        assert.isTrue(Math.abs(base0AtWeek11 - 4031.7139e18) < this.MIN_ERROR);
        const base1AtWeek11 =
            +(await this.Pool.getUserBaseAmount(seller1)).valueOf();
        assert.isTrue(Math.abs(base1AtWeek11 - 7917.7767e18) < this.MIN_ERROR);
        const baseAdminAtWeek11 =
            +(await this.Pool.getUserBaseAmount(poolManager)).valueOf();
        assert.isTrue(Math.abs(baseAdminAtWeek11 - 87.3586e18) < this.MIN_ERROR);

        const collateralAmountAtWeek11 = +(await this.Pool.getCollateralAmount()).valueOf();
        assert.isTrue(Math.abs(collateralAmountAtWeek11 - 22377.3649e18) < this.MIN_ERROR);

        // Capacity: 24754.7298
        const capacityAtWeek11 =
            +(await this.Pool.getCurrentAvailableCapacity(0)).valueOf();
        assert.isTrue(Math.abs(capacityAtWeek11 - 24754.7298e18) <
            this.MIN_ERROR);

        // *** Move to week12.
        await this.Pool.setTimeExtra(3600 * 24 * 84);
        await this.Pool.addPremium(0, {from: anyone});

        // seller0: 4064.8650
        // seller1: 7982.8814
        // poolManager: 98.0769
        const base0AtWeek12 =
            +(await this.Pool.getUserBaseAmount(seller0)).valueOf();
        assert.isTrue(Math.abs(base0AtWeek12 - 4064.8650e18) < this.MIN_ERROR);
        const base1AtWeek12 =
            +(await this.Pool.getUserBaseAmount(seller1)).valueOf();
        assert.isTrue(Math.abs(base1AtWeek12 - 7982.8814e18) < this.MIN_ERROR);
        const baseAdminAtWeek12 =
            +(await this.Pool.getUserBaseAmount(poolManager)).valueOf();
        assert.isTrue(Math.abs(baseAdminAtWeek12 - 98.0769e18) < this.MIN_ERROR);

        const collateralAmountAtWeek12 = +(await this.Pool.getCollateralAmount()).valueOf();
        assert.isTrue(Math.abs(collateralAmountAtWeek12 - 22571.3649e18) < this.MIN_ERROR);

        // Capacity: 25142.7298
        const capacityAtWeek12 =
            +(await this.Pool.getCurrentAvailableCapacity(0)).valueOf();
        assert.isTrue(Math.abs(capacityAtWeek12 - 25142.7298e18) <
            this.MIN_ERROR);

        // *** Move to week13.
        await this.Pool.setTimeExtra(3600 * 24 * 91);
        await this.Pool.addPremium(0, {from: anyone});

        // seller0: 4064.8650
        // seller1: 7982.8814
        // poolManager: 98.0769
        const base0AtWeek13 =
            +(await this.Pool.getUserBaseAmount(seller0)).valueOf();
        assert.isTrue(Math.abs(base0AtWeek13 - 4064.8650e18) < this.MIN_ERROR);
        const base1AtWeek13 =
            +(await this.Pool.getUserBaseAmount(seller1)).valueOf();
        assert.isTrue(Math.abs(base1AtWeek13 - 7982.8814e18) < this.MIN_ERROR);
        const baseAdminAtWeek13 =
            +(await this.Pool.getUserBaseAmount(poolManager)).valueOf();
        assert.isTrue(Math.abs(baseAdminAtWeek13 - 98.0769e18) < this.MIN_ERROR);

        const collateralAmountAtWeek13 = +(await this.Pool.getCollateralAmount()).valueOf();
        assert.isTrue(Math.abs(collateralAmountAtWeek13 - 22571.3649e18) < this.MIN_ERROR);

        // Capacity: 45142.7298
        const capacityAtWeek13 =
            +(await this.Pool.getCurrentAvailableCapacity(0)).valueOf();
        assert.isTrue(Math.abs(capacityAtWeek13 - 45142.7298e18) <
            this.MIN_ERROR);

        // *** Move to week14.
        await this.Pool.setTimeExtra(3600 * 24 * 98);
        await this.Pool.addPremium(0, {from: anyone});

        // Withdraw pending from week4.
        await this.Pool.withdrawPending(seller0, 0, {from: anyone});

        // seller0: 4064.8650
        // seller1: 7982.8814
        // poolManager: 98.0769

        const base0AtWeek14 =
            +(await this.Pool.getUserBaseAmount(seller0)).valueOf();
        assert.isTrue(Math.abs(base0AtWeek14 - 4064.8650e18) < this.MIN_ERROR);
        const base1AtWeek14 =
            +(await this.Pool.getUserBaseAmount(seller1)).valueOf();
        assert.isTrue(Math.abs(base1AtWeek14 - 7982.8814e18) < this.MIN_ERROR);
        const baseAdminAtWeek14 =
            +(await this.Pool.getUserBaseAmount(poolManager)).valueOf();
        assert.isTrue(Math.abs(baseAdminAtWeek14 - 98.0769e18) < this.MIN_ERROR);

        const collateralAmountAtWeek14 = +(await this.Pool.getCollateralAmount()).valueOf();
        assert.isTrue(Math.abs(collateralAmountAtWeek14 - 18506.5000e18) < this.MIN_ERROR);

        // Capacity: 37012.9998
        const capacityAtWeek14 =
            +(await this.Pool.getCurrentAvailableCapacity(0)).valueOf();
        assert.isTrue(Math.abs(capacityAtWeek14 - 37012.9998e18) <
            this.MIN_ERROR);

        // *** Move to week15.
        await this.Pool.setTimeExtra(3600 * 24 * 105);
        await this.Pool.addPremium(0, {from: anyone});

        // Withdraw ready from week4.
        await this.Pool.withdrawReady(seller0, 0, {from: anyone});

        // seller0: 0
        // seller1: 8017.9494
        // seller2: 10471.3400
        // poolManager: 98.5077

        const base0AtWeek15 =
            +(await this.Pool.getUserBaseAmount(seller0)).valueOf();
        assert.isTrue(Math.abs(base0AtWeek15 - 0) < this.MIN_ERROR);
        const base1AtWeek15 =
            +(await this.Pool.getUserBaseAmount(seller1)).valueOf();
        assert.isTrue(Math.abs(base1AtWeek15 - 8017.9494e18) < this.MIN_ERROR);
        const base2AtWeek15 =
            +(await this.Pool.getUserBaseAmount(seller2)).valueOf();
        assert.isTrue(Math.abs(base2AtWeek15 - 10471.3400e18) < this.MIN_ERROR);
        const baseAdminAtWeek15 =
            +(await this.Pool.getUserBaseAmount(poolManager)).valueOf();
        assert.isTrue(Math.abs(baseAdminAtWeek15 - 98.5077e18) < this.MIN_ERROR);

        const collateralAmountAtWeek15 = +(await this.Pool.getCollateralAmount()).valueOf();
        assert.isTrue(Math.abs(collateralAmountAtWeek15 - 18587.7972e18) < this.MIN_ERROR);

        // Capacity: 37175.5944
        const capacityAtWeek15 =
            +(await this.Pool.getCurrentAvailableCapacity(0)).valueOf();
        assert.isTrue(Math.abs(capacityAtWeek15 - 37175.5944e18) <
            this.MIN_ERROR);

        // *** Move to week16.
        await this.Pool.setTimeExtra(3600 * 24 * 112);
        await this.Pool.addPremium(0, {from: anyone});

        // *** Move to week17.
        await this.Pool.setTimeExtra(3600 * 24 * 119);
        await this.Pool.addPremium(0, {from: anyone});

        // Withdraw pending from week7.
        await this.Pool.withdrawPending(seller1, 0, {from: anyone});

        // seller0: 0
        // seller1: 8017.9494
        // seller2: 10471.3400
        // poolManager: 98.5077

        const base0AtWeek17 =
            +(await this.Pool.getUserBaseAmount(seller0)).valueOf();
        assert.isTrue(Math.abs(base0AtWeek17 - 0) < this.MIN_ERROR);
        const base1AtWeek17 =
            +(await this.Pool.getUserBaseAmount(seller1)).valueOf();
        assert.isTrue(Math.abs(base1AtWeek17 - 8017.9494e18) < this.MIN_ERROR);
        const base2AtWeek17 =
            +(await this.Pool.getUserBaseAmount(seller2)).valueOf();
        assert.isTrue(Math.abs(base2AtWeek17 - 10471.3400e18) < this.MIN_ERROR);
        const baseAdminAtWeek17 =
            +(await this.Pool.getUserBaseAmount(poolManager)).valueOf();
        assert.isTrue(Math.abs(baseAdminAtWeek17 - 98.5077e18) < this.MIN_ERROR);

        const collateralAmountAtWeek17 = +(await this.Pool.getCollateralAmount()).valueOf();
        assert.isTrue(Math.abs(collateralAmountAtWeek17 - 13255.7908e18) < this.MIN_ERROR);

        // Capacity: 26511.5817
        const capacityAtWeek17 =
            +(await this.Pool.getCurrentAvailableCapacity(0)).valueOf();
        assert.isTrue(Math.abs(capacityAtWeek17 - 26511.5817e18) <
            this.MIN_ERROR);

        // *** Move to week18.
        await this.Pool.setTimeExtra(3600 * 24 * 126);
        await this.Pool.addPremium(0, {from: anyone});

        // Withdraw ready from week7.
        await this.Pool.withdrawReady(seller1, 0, {from: anyone});

        // seller0: 0
        // seller1: 2707.5509
        // seller2: 10555.5798
        // poolManager: 99.3002
        // fee (in poolManager wallet): 79.5267

        const base0AtWeek18 =
            +(await this.Pool.getUserBaseAmount(seller0)).valueOf();
        assert.isTrue(Math.abs(base0AtWeek18 - 0) < this.MIN_ERROR);
        const base1AtWeek18 =
            +(await this.Pool.getUserBaseAmount(seller1)).valueOf();
        assert.isTrue(Math.abs(base1AtWeek18 - 2707.5509e18) < this.MIN_ERROR);
        const base2AtWeek18 =
            +(await this.Pool.getUserBaseAmount(seller2)).valueOf();
        assert.isTrue(Math.abs(base2AtWeek18 - 10555.5798e18) < this.MIN_ERROR);
        const baseAdminAtWeek18 =
            +(await this.Pool.getUserBaseAmount(poolManager)).valueOf();
        assert.isTrue(Math.abs(baseAdminAtWeek18 - 99.3002e18) < this.MIN_ERROR);
        const feeAtWeek18 = +(await this.USDC.balanceOf(poolManager)).valueOf()
        assert.isTrue(Math.abs(feeAtWeek18 - 79.5267e18) < this.MIN_ERROR);

        const collateralAmountAtWeek18 = +(await this.Pool.getCollateralAmount()).valueOf();
        assert.isTrue(Math.abs(collateralAmountAtWeek18 - 13362.4310e18) < this.MIN_ERROR);

        // Capacity: 26724.8619
        const capacityAtWeek18 =
            +(await this.Pool.getCurrentAvailableCapacity(0)).valueOf();
        assert.isTrue(Math.abs(capacityAtWeek18 - 26724.8619e18) <
            this.MIN_ERROR);
    });
});
