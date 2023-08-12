
const { ethers } = require("hardhat");

async function main() {
    
    const LaunchpadToken = await ethers.getContractFactory("LaunchpadToken");
    const launchToken = await LaunchpadToken.deploy();
    console.log("launchToken: " + launchToken.address);

    //const PaymentToken = await ethers.getContractFactory("USDT");
    //const paymentToken = await PaymentToken.deploy();
    //console.log(paymentToken.address);

    const LaunchpadV1 = await ethers.getContractFactory("LaunchpadV1");
    const launchpad = await LaunchpadV1.deploy();
    console.log("launchpad: " + launchpad.address);

    //const SnapshotStaking = await ethers.getContractFactory("SnapshotStaking");
    //const staking = await SnapshotStaking.deploy();
    //console.log(staking.address);

    //const RewardToken = await ethers.getContractFactory("RewardToken");
    //const reward = await RewardToken.deploy();
    //console.log(reward.address);

    console.log("done.");
}

main()
.then(() => process.exit(0))
.catch((error) => {
console.error(error);
process.exit(1);
});