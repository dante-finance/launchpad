const { expect } = require("chai");
const { loadFixture, time, helpers } = require("@nomicfoundation/hardhat-network-helpers");
const { ethers } = require("hardhat");
const { string } = require("hardhat/internal/core/params/argumentTypes");
const { BigInteger } = require("bignumber/lib/rsa");
const { seconds } = require("@nomicfoundation/hardhat-network-helpers/dist/src/helpers/time/duration");

describe("Launchpad V1 contract", function () {

    async function deploy() {
        const [owner, addr1, addr2] = await ethers.getSigners();
    
        var now = await time.latest();

        const Token = await ethers.getContractFactory("Token");
        const token = await Token.deploy(
            now,
            owner.address,
            owner.address
        );

        const LaunchpadToken = await ethers.getContractFactory("LaunchpadToken");
        const launchToken = await LaunchpadToken.deploy();

        const PaymentToken = await ethers.getContractFactory("PaymentToken");
        const paymentToken = await PaymentToken.deploy();

        const LaunchpadV1 = await ethers.getContractFactory("LaunchpadV1");
    
        const launchpad = await LaunchpadV1.deploy();

        await launchToken.transfer(launchpad.address, "10000000000000000000000");
        await paymentToken.transfer(addr1.address, formatUSDC(1500));

        await launchpad.init(
            launchToken.address,
            paymentToken.address,
            [0, 30],
            [20, 80]
        );

        return { owner, addr1, token, launchToken, paymentToken, launchpad };
    }

    it("deploy", async function () {
        const { token, launchpad } = await loadFixture(deploy);

        expect(await launchpad.vestingStartTimestamp()).to.equal(0);
    });

    it("claim & release", async function() {
        const { owner, token, launchToken, paymentToken, launchpad } = await loadFixture(deploy);

        await launchpad.setAllocations(
            [owner.address],
            [format(1000)]
        );

        expect(await launchpad.allocated(owner.address) == format(1000));
        
        await launchpad.setStartTime(
            await time.latest(),
            30,
            60,
            80
        );

        await paymentToken.approve(launchpad.address, formatUSDC(800));

        await launchpad.claimWhitelist(format(500));

        expect(await launchpad.claims(owner.address, 0)).eq(format(100));
        expect(await launchpad.claims(owner.address, 30)).eq(format(400));
        expect(await launchpad.allocated(owner.address)).eq(format(500));

        await launchpad.claimWhitelist(format(500));

        expect(await launchpad.claims(owner.address, 0)).eq(format(200));
        expect(await launchpad.claims(owner.address, 30)).eq(format(800));
        expect(await launchpad.allocated(owner.address)).eq(0);

        let timestamp = await time.latest();
        await launchpad.setStartDistributionTime(timestamp);

        expect(await launchpad.releasableAt(owner.address, 0, timestamp)).eq(format(200));
        expect(await launchpad.releasableAt(owner.address, 30, timestamp)).eq(format(0));

        expect(await launchpad.releasableAt(owner.address, 0, timestamp + 15)).eq(format(200));
        expect(await launchpad.releasableAt(owner.address, 30, timestamp + 15)).eq(format(400));

        expect(await launchpad.releasableAt(owner.address, 0, timestamp + 30)).eq(format(200));
        expect(await launchpad.releasableAt(owner.address, 30, timestamp + 30)).eq(format(800));

        await skipTimeTo(timestamp + 15);
        await launchpad.release();
        expect(await launchToken.balanceOf(owner.address)).eq(format(600));

        await skipTimeTo(timestamp + 30);
        await launchpad.release();
        expect(await launchToken.balanceOf(owner.address)).eq(format(1000));

        await skipTimeTo(timestamp + 45);
        await launchpad.release();
        expect(await launchToken.balanceOf(owner.address)).eq(format(1000));
    });

    it("start before allocations", async function(){
        const { owner, token, launchToken, paymentToken, launchpad } = await loadFixture(deploy);

        await expect(launchpad.setStartTime(
            await time.latest(),
            30,
            60,
            80)
        ).to.be.revertedWith("Allocations not yet distributed.");
    });
    
    it("user without allocations cannot claim in whitelist phase", async function(){
        const { owner, addr1, token, launchToken, paymentToken, launchpad } = await loadFixture(deploy);

        await launchpad.setAllocations(
            [owner.address],
            [format(1000)]
        );

        await launchpad.setStartTime(
            await time.latest(),
            30,
            60,
            80
        );

        await paymentToken.connect(addr1).approve(launchpad.address, formatUSDC(800));
        
        await expect(launchpad
            .connect(addr1)
            .claimWhitelist(format(500)))
            .to.be.revertedWith("User does not have a whitelist allocation.");
    });

    it("non whitelisted user cannot claim before FCFS phase", async function(){
        const { owner, addr1, token, launchToken, paymentToken, launchpad } = await loadFixture(deploy);

        await launchpad.setAllocations(
            [owner.address],
            [format(1000)]
        );

        await launchpad.setStartTime(
            await time.latest(),
            30,
            60,
            80
        );

        // still whitelist phase
        await skipTime(15);

        await paymentToken.connect(addr1).approve(launchpad.address, formatUSDC(1000));
        
        await expect(launchpad.connect(addr1).claim(format(1000))).to.be.reverted;
    });

    it("non whitelisted user can claim in FCFS phase", async function(){
        const { owner, addr1, token, launchToken, paymentToken, launchpad } = await loadFixture(deploy);

        await launchpad.setAllocations(
            [owner.address],
            [format(1000)]
        );

        await launchpad.setStartTime(
            await time.latest(),
            30,
            60,
            80
        );

        await skipTime(30);

        await paymentToken.connect(addr1).approve(launchpad.address, formatUSDC(800));
        
        await launchpad.connect(addr1).claim(format(500));

        expect(await launchpad.claims(addr1.address, 0)).eq(format(100));
        expect(await launchpad.claims(addr1.address, 30)).eq(format(400));
    });

    it("user did not appove enough funds to claim", async function(){
        const { owner, addr1, token, launchToken, paymentToken, launchpad } = await loadFixture(deploy);

        await launchpad.setAllocations(
            [owner.address],
            [format(1000)]
        );

        await launchpad.setStartTime(
            await time.latest(),
            30,
            60,
            80
        );

        await skipTime(30);

        await paymentToken.connect(addr1).approve(launchpad.address, formatUSDC(1000));
        
        await expect(launchpad.connect(addr1).claim(format(1500))).to.be.reverted; 
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