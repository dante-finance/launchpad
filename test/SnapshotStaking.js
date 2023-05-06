const { expect } = require("chai");
const { loadFixture, time, helpers } = require("@nomicfoundation/hardhat-network-helpers");
const { ethers } = require("hardhat");
const { string } = require("hardhat/internal/core/params/argumentTypes");
const { BigInteger } = require("bignumber/lib/rsa");
const { seconds } = require("@nomicfoundation/hardhat-network-helpers/dist/src/helpers/time/duration");
const { BigNumber } = require("@ethersproject/bignumber");

describe("Snapshot staking contract", function () {

    async function deploy() {
        const [owner, addr1, addr2] = await ethers.getSigners();
    
        const SnapshotStaking = await ethers.getContractFactory("SnapshotStaking");
        const staking = await SnapshotStaking.deploy();
        
        const Token = await ethers.getContractFactory("Token");
        const token = await Token.deploy(
            await time.latest(),
            owner.address,
            owner.address
        );
        
        let start = await time.latest() + 1;

        await staking.addPool(
            token.address,
            token.address,
            format(10000),
            start,
            start + 31536000,
            800
        );

        await token.transfer(staking.address, format(5000));

        return { owner, staking, token };
    }

    it("deploy", async function () {
        const { staking } = await loadFixture(deploy);

        expect(await staking.poolLength()).to.equal(1);
    });

    it("stake", async function () {
        const { owner, staking, token } = await loadFixture(deploy);

        await token.approve(staking.address, format(1000));

        await staking.stake(
            0, 
            format(1000)
        );

        let user = await staking.userInfo(0, owner.address);

        expect(user.amount).be.eq(format(1000));
        expect(user.available).be.eq(format(1000));

        await skipTime(31536000);

        await staking.unstakeRequest(0, format(400));

        await skipTime(60);

        await staking.unstakeRequest(0, format(600));

        let unlock = await staking.getUserUnlocks(0);

        var array = [];
        for(var i = 0; i < unlock.length; i++) {
            array.push(unlock[i].toString());
        }

        expect((await staking.getUserUnlockAmount(0, array[0])).toString())
            .eq(format(400));

        expect((await staking.getUserUnlockAmount(0, array[1])).toString())
            .eq(format(600));

        await skipTime(302400);

        await expect(staking.withdraw(0)).to.be.revertedWith("No scheduled withdrawals");

        // skip a week
        await skipTime(302400);

        let oldBalance = BigNumber.from((await token.balanceOf(owner.address)).toString());

        await staking.withdraw(0);

        let newBalance = BigNumber.from((await token.balanceOf(owner.address)).toString());

        expect(oldBalance.add(BigNumber.from(format(400)))).eq(BigNumber.from(format(4400)));

        expect((await staking.getUserUnlockAmount(0, array[0])))
            .eq(0); 
    });
});

function format(number) {
    return number.toString() + "000000000000000000";
}

function formatUSDC(number) {
    return number.toString() + "000000";
}

async function skipTime(seconds) {
    await time.setNextBlockTimestamp(await time.latest() + seconds);
}

async function skipTimeTo(seconds) {
    await time.setNextBlockTimestamp(seconds);
}