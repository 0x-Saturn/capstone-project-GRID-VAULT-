const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("GridVault", function () {
  let MockERC20, GridVault, token, vault, owner, user;

  beforeEach(async function () {
    [owner, user] = await ethers.getSigners();

    MockERC20 = await ethers.getContractFactory("MockERC20");
    GridVault = await ethers.getContractFactory("GridVault");

    token = await MockERC20.deploy("Mock", "MCK", ethers.parseEther("1000000"));
    await token.waitForDeployment();

    vault = await GridVault.deploy(owner.address);
    await vault.waitForDeployment();
  });

  it("estimate simple", async function () {
    const lower = ethers.parseEther("1");
    const upper = ethers.parseEther("2");
    const grid = 1;
    const amount = ethers.parseEther("1");

    const profit = await vault.estimatePositionProfit(lower, upper, grid, amount);
    expect(profit).to.equal(ethers.parseEther("1"));
  });

  it("create and close", async function () {
    const amount = ethers.parseEther("1000");
    // mint to user
    await token.mint(user.address, amount);
    // approve vault from user
    await token.connect(user).approve(await vault.getAddress(), amount);

    const lower = ethers.parseEther("1");
    const upper = ethers.parseEther("2");
    const grid = 2;

    await vault.connect(user).createPosition(await token.getAddress(), lower, upper, grid, amount);

    const pid = 1;
    const pos = await vault.getPosition(pid);
    expect(pos.active).to.equal(true);

    await vault.connect(user).closePosition(pid);
    const pos2 = await vault.getPosition(pid);
    expect(pos2.active).to.equal(false);

    expect(await token.balanceOf(user.address)).to.equal(amount);
  });
});
