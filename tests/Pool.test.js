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

contract('Pool', ([admin, seller0, seller1, buyer0, buyer1]) => {
    beforeEach(async () => {
        this.USDC = await MockERC20.new("USDC", "USDC", decToHex(1000000), {from: admin});
        this.Tidal = await MockERC20.new("Tidal", "TIDAL", decToHex(1000000), {from: admin});
        await this.USDC.transfer(seller0, decToHex(200000), {from: admin});
        await this.USDC.transfer(seller1, decToHex(300000), {from: admin});
        await this.USDC.transfer(buyer0, decToHex(1000), {from: admin});
        await this.USDC.transfer(buyer1, decToHex(1000), {from: admin});

        this.Pool = await Pool.new(this.USDC.address, this.Tidal.address, true, {from: admin});
        await this.Pool.setAdmin(admin, {from: admin});
        await this.Pool.setPool(10, 1, 10, 0, 0, 0, 1, "", "", {from: admin});

        // Adds policy.
        await this.Pool.addPolicy(500000, 200, "Metamask", "Bla bla");
        await this.Pool.addPolicy(1000000, 300, "Rainbow", "Bla bla");
    });

    it('should work', async () => {
        const currentWeek = (await this.Pool.getCurrentWeek()).valueOf();

        // In week0, seller0 deposits 100,000 USDC.
        await this.USDC.approve(this.Pool.address, decToHex(100000), {from: seller0});
        await this.Pool.deposit(decToHex(100000), {from: seller0});

        // Buyer0 buys 20,000 USDC worth of Metamask policy, from Sunday, for 3 weeks.
        // It should costs 4 USDC per week, totally 12 USDC for 3 weeks.
        await this.USDC.approve(this.Pool.address, decToHex(12), {from: buyer0});
        await this.Pool.buy(0, decToHex(20000), currentWeek + 1, currentWeek + 4, {from: buyer0});

        // Move to week1.
        await this.Pool.setTimeExtra(3600 * 24 * 7);
        await this.Pool.addPremium(0);
        await this.Pool.addPremium(1);

        // So far there should be no premium paid yet.
        const baseAtWeek1 = await this.Pool.getUserBaseAmount(seller0);
        assert.equal(baseAtWeek1.valueOf(), 100000e18);
    });
});
