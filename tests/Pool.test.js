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
        admin, seller0, seller1, buyer0, buyer1, anyone,
        treasury, voter0, voter1, voter2]) => {

    beforeEach(async () => {
        this.USDC = await MockERC20.new(
            "USDC", "USDC", decToHex(502000), {from: admin});
        this.Tidal = await MockERC20.new(
            "Tidal", "TIDAL", decToHex(1000000), {from: admin});
        await this.USDC.transfer(seller0, decToHex(200000), {from: admin});
        await this.USDC.transfer(seller1, decToHex(300000), {from: admin});
        await this.USDC.transfer(buyer0, decToHex(1000), {from: admin});
        await this.USDC.transfer(buyer1, decToHex(1000), {from: admin});

        this.Pool = await Pool.new(
            this.USDC.address, this.Tidal.address, true, {from: admin});
        await this.Pool.setAdmin(admin, {from: admin});
        await this.Pool.addToCommittee(voter0, {from: admin});
        await this.Pool.addToCommittee(voter1, {from: admin});
        await this.Pool.addToCommittee(voter2, {from: admin});

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
            {from: admin}
        );

        // Adds policy.
        await this.Pool.addPolicy(500000, 200, "Metamask", "Bla bla", {from: admin});
        await this.Pool.addPolicy(1000000, 300, "Rainbow", "Bla bla", {from: admin});

        // Defines minimum floating-point calculation error.
        this.MIN_ERROR = 0.0001e18; // 0.0001 USDC
    });

    it('should work', async () => {
        const currentWeek = +(await this.Pool.getCurrentWeek()).valueOf();

        // In week0, seller0 deposits 100,000 USDC.
        await this.USDC.approve(
            this.Pool.address, decToHex(100000), {from: seller0});
        await this.Pool.deposit(decToHex(100000), {from: seller0});

        // Buyer0 buys 20,000 USDC worth of Metamask policy, from Sunday,
        // for 3 weeks.
        // It should cost 4 USDC per week, totally 12 USDC for 3 weeks.
        await this.USDC.approve(
            this.Pool.address, decToHex(12), {from: buyer0});
        await this.Pool.buy(
            0,
            decToHex(20000),
            currentWeek + 1,
            currentWeek + 4,
            {from: buyer0}
        );

        // *** Move to week1.
        await this.Pool.setTimeExtra(3600 * 24 * 7);
        await this.Pool.addPremium(0, {from: anyone});
        await this.Pool.addPremium(1, {from: anyone});

        // So far there should be 4 USDC premium.
        // 92% of it, or 3.68 goes to sellers
        // 5% of it, or 0.2 goes to managementFee1
        // 3% of it, or 0.12 goes to managementFee2
        const baseAtWeek1 =
            +(await this.Pool.getUserBaseAmount(seller0)).valueOf();
        assert.isTrue(Math.abs(baseAtWeek1 - 100003.68e18) < this.MIN_ERROR);

        // Capacity should be (100,003.68 + 0.2) / 50% - 20,000 = 180007.76
        const capacityAtWeek1 =
            +(await this.Pool.getCurrentAvailableCapacity(0)).valueOf();
        assert.isTrue(Math.abs(capacityAtWeek1 - 180007.76e18) <
            this.MIN_ERROR);

        // *** Move to week2.
        await this.Pool.setTimeExtra(3600 * 24 * 14);
        await this.Pool.addPremium(0, {from: anyone});
        await this.Pool.addPremium(1, {from: anyone});

        // seller0 now withdraws 30,000 USDC.
        await this.Pool.withdraw(decToHex(30000), {from: seller0});

        // So far there should be 8 premium.
        // 92% of it, or 7.36 goes to sellers
        // 5% of it, or 0.4 goes to managementFee1
        // 3% of it, or 0.24 goes to managementFee2
        const baseAtWeek2 =
            +(await this.Pool.getUserBaseAmount(seller0)).valueOf();
        assert.isTrue(Math.abs(baseAtWeek2 - 100007.36e18) < this.MIN_ERROR);

        // Capacity should be (100,007.36 + 0.4) / 50% - 20,000 = 180,015.52
        const capacityAtWeek2 =
            +(await this.Pool.getCurrentAvailableCapacity(0)).valueOf();
        assert.isTrue(Math.abs(capacityAtWeek2 - 180015.52e18) <
            this.MIN_ERROR);

        // *** Move to week5.
        for (let i = 3; i <= 5; ++i) {
            await this.Pool.setTimeExtra(3600 * 24 * 7 * i);
            await this.Pool.addPremium(0, {from: anyone});
            await this.Pool.addPremium(1, {from: anyone});
        }

        // So far there should be 12 premium.
        // 92% of it, or 11.04 goes to sellers
        // 5% of it, or 0.6 goes to managementFee1
        // 3% of it, or 0.36 goes to managementFee2
        const baseAtWeek5 =
            +(await this.Pool.getUserBaseAmount(seller0)).valueOf();
        assert.isTrue(Math.abs(baseAtWeek5 - 100011.04e18) < this.MIN_ERROR);

        // Capacity should be (100,011.04 + 0.6) / 50% = 200,023.28
        const capacityAtWeek5 =
            +(await this.Pool.getCurrentAvailableCapacity(0)).valueOf();
        assert.isTrue(Math.abs(capacityAtWeek5 - 200023.28e18) <
            this.MIN_ERROR);

        // *** Move to week11.
        for (let i = 6; i <= 11; ++i) {
            await this.Pool.setTimeExtra(3600 * 24 * 7 * i);
            await this.Pool.addPremium(0, {from: anyone});
            await this.Pool.addPremium(1, {from: anyone});
        }

        // Calling withdrawPending, by anyone, should revert.
        await expectRevert(
            this.Pool.withdrawPending(seller0, 0, {from: anyone}),
            "Not ready yet"
        );

        // Capacity should be (100,011.04 + 0.6) / 50% = 200,023.28
        const capacityAtWeek11 =
            +(await this.Pool.getCurrentAvailableCapacity(0)).valueOf();
        assert.isTrue(Math.abs(capacityAtWeek11 - 200023.28e18) <
            this.MIN_ERROR);

        // *** Move to week12.
        await this.Pool.setTimeExtra(3600 * 24 * 7 * 12);
        await this.Pool.addPremium(0, {from: anyone});
        await this.Pool.addPremium(1, {from: anyone});

        // Calling withdrawPending, by anyone.
        await this.Pool.withdrawPending(seller0, 0, {from: anyone});

        // Calling withdrawReady, by anyone, should revert.
        await expectRevert(
            this.Pool.withdrawReady(seller0, 0, {from: anyone}),
            "Not ready yet"
        );

        // Capacity should be (100,011.04 + 0.6 - 30,000) / 50% = 140,023.28
        const capacityAtWeek12 =
            +(await this.Pool.getCurrentAvailableCapacity(0)).valueOf();
        assert.isTrue(Math.abs(capacityAtWeek12 - 140023.28e18) <
            this.MIN_ERROR);

        // *** Move to week13.
        await this.Pool.setTimeExtra(3600 * 24 * 7 * 13);
        await this.Pool.addPremium(0, {from: anyone});
        await this.Pool.addPremium(1, {from: anyone});

        // Calling withdrawReady, by anyone.
        await this.Pool.withdrawReady(seller0, 0, {from: anyone});

        // Seller0 should have 100,000 + 30,000 * 98% = 129,400 USDC in
        // his wallet now.
        const seller0BalanceAtWeek13 =
            +(await this.USDC.balanceOf(seller0)).valueOf();
        assert.isTrue(Math.abs(seller0BalanceAtWeek13 - 129400e18) <
            this.MIN_ERROR);

        // Totally 30,000 * 2% = 600 USDC goes to everyone.
        // Capacity should be (100,011.04 + 0.6 - 30,000 + 600) / 50% = 141,223.28
        const capacityAtWeek13 =
            +(await this.Pool.getCurrentAvailableCapacity(0)).valueOf();
        assert.isTrue(Math.abs(capacityAtWeek13 - 141223.28e18) <
            this.MIN_ERROR);

        // Admin has 0.36 USDC.
        const adminBalanceAtWeek13 =
            +(await this.USDC.balanceOf(admin)).valueOf();
        assert.isTrue(Math.abs(adminBalanceAtWeek13 - 0.36e18) <
            this.MIN_ERROR);
    });

    it('claim and refund', async () => {
        const currentWeek = +(await this.Pool.getCurrentWeek()).valueOf();

        // In week0, seller0 deposits 100,000 USDC.
        await this.USDC.approve(
            this.Pool.address, decToHex(100000), {from: seller0});
        await this.Pool.deposit(decToHex(100000), {from: seller0});

        // Buyer0 buys 80,000 USDC worth of Metamask policy, from Sunday,
        // for 3 weeks.
        // It should cost 16 USDC per week, totally 48 USDC for 3 weeks.
        await this.USDC.approve(
            this.Pool.address, decToHex(48), {from: buyer0});
        await this.Pool.buy(
            0,
            decToHex(80000),
            currentWeek + 1,
            currentWeek + 4,
            {from: buyer0}
        );

        // *** Move forward to week1.
        await this.Pool.setTimeExtra(3600 * 24 * 7);
        await this.Pool.addPremium(0, {from: anyone});
        await this.Pool.addPremium(1, {from: anyone});

        await this.Pool.setTimeExtra(3600 * 24 * (7 * 1 + 6));

        // A hack happens on the 6th day of week1.
        // Here we wanna test the case that claim and execution are in
        // different weeks.
        // Assume that there are 70,000 loss.
        // Admin claims (currently only admin can claim) to pay to treasury.
        await this.Pool.claim(0, decToHex(70000), treasury, {from: admin});

        const claimRequestLength =
            +(await this.Pool.getClaimRequestLength({from: anyone})).valueOf();
        assert.equal(claimRequestLength, 1);

        // Without voting, execution should revert.
        await expectRevert(
            this.Pool.execute(0, {from: anyone}),
            "Not enough votes"
        );

        // Move forward one more day to week2.
        await this.Pool.setTimeExtra(3600 * 24 * 7 * 2);
        await this.Pool.addPremium(0, {from: anyone});
        await this.Pool.addPremium(1, {from: anyone});

        // Now vote and execute.
        // Two out of three voters support the claim.
        await this.Pool.vote(0, 1, {from: voter0});
        await this.Pool.vote(0, 1, {from: voter1});
        await this.Pool.execute(0, {from: anyone});

        // Executing again will revert.
        await expectRevert(
            this.Pool.execute(0, {from: anyone}),
            "Already executed"
        );

        // Treasury receives 70,000 USDC.
        const treaturyBalance =
            +(await this.USDC.balanceOf(treasury)).valueOf();
        assert.equal(treaturyBalance, 70000e18);

        // Moves to week3.
        await this.Pool.setTimeExtra(3600 * 24 * 7 * 3);
        await this.Pool.addPremium(0, {from: anyone});
        await this.Pool.addPremium(1, {from: anyone});

        // The premium in record is 16 USDC.
        const coverage = await this.Pool.coverageMap(
            0, currentWeek + 3, buyer0);
        assert.equal(+coverage.premium.valueOf(), 16e18);

        const allCovered =
            +(await this.Pool.coveredMap(0, currentWeek + 3)).valueOf();
        assert.equal(allCovered, 80000e18);

        // Because now there are only 30,000 + 32 * 0.97 = 30030.92 USDC in
        // the pool, which equals to 30030.92 / 50% = 60061.84 USDC coverage,
        // buyer0 should be able to get 19938.16 USDC of coverage refunded,
        // which is 3.987632 USDC.
        await this.Pool.refund(0, currentWeek + 3, buyer0, {from: anyone});

        // buyer0 should now have 1000 - 48 + 3.987632 = 955.987632 USDC
        const buyer0BalanceAtWeek3 =
            +(await this.USDC.balanceOf(buyer0)).valueOf();
        assert.isTrue(Math.abs(buyer0BalanceAtWeek3 - 955.987632e18) <
            this.MIN_ERROR);
    });
});
