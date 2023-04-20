const { expect } = require("chai");
const { loadFixture, time } = require("@nomicfoundation/hardhat-network-helpers");
const { ethers } = require("hardhat");
const { string } = require("hardhat/internal/core/params/argumentTypes");

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

        await staking.unStakeRequest(0, format(1000));
        let pending = await staking.pendingReward(0, owner.address);

        console.log(pending);
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