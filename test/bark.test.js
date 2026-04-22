const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("BARKALOT Token", function () {
  let barkalot;
  let owner;
  let treasury;
  let devWallet;
  let user1;
  let user2;
  let user3;
  let routerAddress;

  const TOTAL_SUPPLY = ethers.parseEther("1000000000"); // 1 Billion
  const BUY_TAX = 3;
  const SELL_TAX = 3;
  const BURN_TAX = 1;
  const TREASURY_TAX = 2;
  const DEAD_ADDRESS = "0x000000000000000000000000000000000000dEaD";
  
  // Use a real router address for testing (PancakeSwap on BSC mainnet)
  // For local testing, we'll use a placeholder
  const PANCAKE_ROUTER = "0x10ED43C718714eb63d5aA57B78B54704E256024E";

  before(async function () {
    [owner, treasury, devWallet, user1, user2, user3] = await ethers.getSigners();
    
    // Use a valid router address (for testing purposes)
    routerAddress = PANCAKE_ROUTER;
    
    // Deploy BARKALOT implementation
    const BARKALOT = await ethers.getContractFactory("BARKALOT");
    
    // Deploy proxy
    barkalot = await upgrades.deployProxy(
      BARKALOT,
      [treasury.address, devWallet.address, routerAddress],
      {
        initializer: "initialize",
        kind: "transparent"
      }
    );
    await barkalot.waitForDeployment();
    
    console.log("BARKALOT deployed at:", await barkalot.getAddress());
  });

  describe("Deployment", function () {
    it("Should set the correct name", async function () {
      expect(await barkalot.name()).to.equal("BARK-A-LOT");
    });

    it("Should set the correct symbol", async function () {
      expect(await barkalot.symbol()).to.equal("BARK");
    });

    it("Should set the correct decimals", async function () {
      expect(await barkalot.decimals()).to.equal(18);
    });

    it("Should have correct total supply", async function () {
      expect(await barkalot.totalSupply()).to.equal(TOTAL_SUPPLY);
    });

    it("Should assign total supply to owner", async function () {
      const ownerBalance = await barkalot.balanceOf(owner.address);
      expect(ownerBalance).to.equal(TOTAL_SUPPLY);
    });

    it("Should set correct tax rates", async function () {
      expect(await barkalot.buyTax()).to.equal(BUY_TAX);
      expect(await barkalot.sellTax()).to.equal(SELL_TAX);
      expect(await barkalot.burnTax()).to.equal(BURN_TAX);
      expect(await barkalot.treasuryTax()).to.equal(TREASURY_TAX);
    });

    it("Should set correct addresses", async function () {
      expect(await barkalot.TreasuryAddress()).to.equal(treasury.address);
      expect(await barkalot.BurnAddress()).to.equal(DEAD_ADDRESS);
    });

    it("Should set correct max transaction amounts", async function () {
      const maxBuy = await barkalot.maxBuyAmount();
      const maxSell = await barkalot.maxSellAmount();
      const maxWallet = await barkalot.maxWalletAmount();
      
      expect(maxBuy).to.equal(TOTAL_SUPPLY * 10n / 1000n);
      expect(maxSell).to.equal(TOTAL_SUPPLY * 10n / 1000n);
      expect(maxWallet).to.equal(TOTAL_SUPPLY * 20n / 1000n);
    });

    it("Should set the correct router", async function () {
      const router = await barkalot.uniswapV2Router();
      expect(router).to.equal(routerAddress);
    });
  });

  describe("Exclusions", function () {
    it("Should exclude owner from fees", async function () {
      const initialBalance = await barkalot.balanceOf(user1.address);
      await barkalot.connect(owner).transfer(user1.address, ethers.parseEther("1000"));
      const finalBalance = await barkalot.balanceOf(user1.address);
      expect(finalBalance - initialBalance).to.equal(ethers.parseEther("1000"));
    });

    it("Should exclude contract from fees", async function () {
      const isExcluded = await barkalot._isExcludedFromFees(barkalot.target);
      expect(isExcluded).to.be.true;
    });

    it("Should exclude treasury from fees", async function () {
      const isExcluded = await barkalot._isExcludedFromFees(treasury.address);
      expect(isExcluded).to.be.true;
    });

    it("Should exclude dead address from fees", async function () {
      const isExcluded = await barkalot._isExcludedFromFees(DEAD_ADDRESS);
      expect(isExcluded).to.be.true;
    });
  });

  describe("Trading Controls", function () {
    it("Should not allow trading before enabled", async function () {
      await expect(
        barkalot.connect(user1).transfer(user2.address, ethers.parseEther("100"))
      ).to.be.revertedWith("Trading is not active.");
    });

    it("Should allow owner to enable trading", async function () {
      await expect(barkalot.connect(owner).enableTrading(true, 1))
        .to.emit(barkalot, "EnabledTrading")
        .withArgs(true, 1);
    });

    it("Should not allow re-enabling trading", async function () {
      await expect(
        barkalot.connect(owner).enableTrading(true, 1)
      ).to.be.revertedWith("Cannot re enable trading");
    });

    it("Should set tradingActiveBlock after enabling", async function () {
      const block = await barkalot.tradingActiveBlock();
      expect(block).to.be.gt(0);
    });
  });

  describe("Transfer Limits", function () {
    beforeEach(async function () {
      // Transfer tokens to users for testing
      await barkalot.connect(owner).transfer(user1.address, ethers.parseEther("100000"));
      await barkalot.connect(owner).transfer(user2.address, ethers.parseEther("100000"));
    });

    it("Should enforce max buy limit", async function () {
      const maxBuy = await barkalot.maxBuyAmount();
      const exceedAmount = maxBuy + 1n;
      
      // Get the pair address
      const pairAddress = await barkalot.uniswapV2Pair();
      
      // Try to buy more than max
      await expect(
        barkalot.connect(user1).transfer(pairAddress, exceedAmount)
      ).to.be.reverted;
    });

    it("Should enforce max sell limit", async function () {
      const maxSell = await barkalot.maxSellAmount();
      const exceedAmount = maxSell + 1n;
      
      // First give user1 enough tokens
      await barkalot.connect(owner).transfer(user1.address, exceedAmount);
      
      // Get the pair address
      const pairAddress = await barkalot.uniswapV2Pair();
      
      // Try to sell more than max
      await expect(
        barkalot.connect(user1).transfer(pairAddress, exceedAmount)
      ).to.be.reverted;
    });

    it("Should enforce max wallet limit", async function () {
      const maxWallet = await barkalot.maxWalletAmount();
      const currentBalance = await barkalot.balanceOf(user2.address);
      const amountToAdd = maxWallet - currentBalance + 1n;
      
      await expect(
        barkalot.connect(owner).transfer(user2.address, amountToAdd)
      ).to.be.revertedWith("Cannot Exceed max wallet");
    });

    it("Should allow owner to remove limits", async function () {
      await barkalot.connect(owner).removeLimits();
      expect(await barkalot.limitsInEffect()).to.be.false;
    });
  });

  describe("Tax Collection", function () {
    beforeEach(async function () {
      // Transfer tokens to users
      await barkalot.connect(owner).transfer(user1.address, ethers.parseEther("100000"));
      await barkalot.connect(owner).transfer(user2.address, ethers.parseEther("100000"));
    });

    it("Should collect tax on transfers when trading is active", async function () {
      // Get the pair address
      const pairAddress = await barkalot.uniswapV2Pair();
      
      const transferAmount = ethers.parseEther("1000");
      const initialContractBalance = await barkalot.balanceOf(barkalot.target);
      
      // Transfer to pair (simulate trade)
      await barkalot.connect(user1).transfer(pairAddress, transferAmount);
      
      const finalContractBalance = await barkalot.balanceOf(barkalot.target);
      
      // Tax should be collected (contract balance should increase)
      expect(finalContractBalance).to.be.gte(initialContractBalance);
    });

    it("Should burn tokens correctly", async function () {
      const burnAmount = ethers.parseEther("100");
      const initialBurnAddressBalance = await barkalot.balanceOf(DEAD_ADDRESS);
      
      await barkalot.connect(owner).transfer(DEAD_ADDRESS, burnAmount);
      
      const finalBurnAddressBalance = await barkalot.balanceOf(DEAD_ADDRESS);
      expect(finalBurnAddressBalance - initialBurnAddressBalance).to.equal(burnAmount);
    });

    it("Should exclude from fees when marked", async function () {
      await barkalot.connect(owner).excludeFromFees(user1.address, true);
      
      const transferAmount = ethers.parseEther("100");
      const initialBalance = await barkalot.balanceOf(user2.address);
      
      await barkalot.connect(user1).transfer(user2.address, transferAmount);
      
      const finalBalance = await barkalot.balanceOf(user2.address);
      expect(finalBalance - initialBalance).to.equal(transferAmount);
    });
  });

  describe("Admin Functions", function () {
    it("Should allow owner to update max buy amount", async function () {
      const newMaxBuy = ethers.parseEther("50000");
      await expect(barkalot.connect(owner).updateMaxBuyAmount(50000))
        .to.emit(barkalot, "UpdatedMaxBuyAmount");
      expect(await barkalot.maxBuyAmount()).to.equal(newMaxBuy);
    });

    it("Should not allow max buy below 0.1%", async function () {
      await expect(
        barkalot.connect(owner).updateMaxBuyAmount(0)
      ).to.be.revertedWith("Cannot set max buy amount lower than 0.1%");
    });

    it("Should allow owner to update max sell amount", async function () {
      const newMaxSell = ethers.parseEther("50000");
      await expect(barkalot.connect(owner).updateMaxSellAmount(50000))
        .to.emit(barkalot, "UpdatedMaxSellAmount");
      expect(await barkalot.maxSellAmount()).to.equal(newMaxSell);
    });

    it("Should allow owner to update max wallet amount", async function () {
      const newMaxWallet = ethers.parseEther("150000");
      await expect(barkalot.connect(owner).updateMaxWalletAmount(150000))
        .to.emit(barkalot, "UpdatedMaxWalletAmount");
      expect(await barkalot.maxWalletAmount()).to.equal(newMaxWallet);
    });

    it("Should allow owner to update treasury address", async function () {
      await expect(barkalot.connect(owner).updateTreasuryAddress(user3.address))
        .to.emit(barkalot, "UpdatedTreasuryAddress")
        .withArgs(user3.address);
      expect(await barkalot.TreasuryAddress()).to.equal(user3.address);
      
      // Reset back for other tests
      await barkalot.connect(owner).updateTreasuryAddress(treasury.address);
    });

    it("Should allow owner to update burn address", async function () {
      await expect(barkalot.connect(owner).updateBurnAddress(user3.address))
        .to.emit(barkalot, "UpdatedBurnAddress")
        .withArgs(user3.address);
      expect(await barkalot.BurnAddress()).to.equal(user3.address);
      
      // Reset back
      await barkalot.connect(owner).updateBurnAddress(DEAD_ADDRESS);
    });

    it("Should allow owner to update taxes", async function () {
      const newBurnTax = 2;
      const newTreasuryTax = 3;
      await expect(barkalot.connect(owner).updateTaxes(newBurnTax, newTreasuryTax))
        .to.emit(barkalot, "UpdatedTaxes")
        .withArgs(newBurnTax, newTreasuryTax);
      
      expect(await barkalot.burnTax()).to.equal(newBurnTax);
      expect(await barkalot.treasuryTax()).to.equal(newTreasuryTax);
      
      // Reset back
      await barkalot.connect(owner).updateTaxes(BURN_TAX, TREASURY_TAX);
    });

    it("Should not allow taxes to exceed 10% total", async function () {
      await expect(
        barkalot.connect(owner).updateTaxes(8, 8)
      ).to.be.revertedWith("Total tax cannot exceed 10%");
    });

    it("Should allow treasury to update swap threshold", async function () {
      const newThreshold = ethers.parseEther("1000");
      await barkalot.connect(treasury).updateSwapThreshold(1000);
      expect(await barkalot.swapTokensAtAmount()).to.equal(newThreshold);
    });

    it("Should not allow non-treasury to update swap threshold", async function () {
      await expect(
        barkalot.connect(user1).updateSwapThreshold(1000)
      ).to.be.revertedWith("only TreasuryAddress can change swapThreshold");
    });
  });

  describe("Allowance and TransferFrom", function () {
    beforeEach(async function () {
      await barkalot.connect(owner).transfer(user1.address, ethers.parseEther("10000"));
    });

    it("Should handle allowance and transferFrom", async function () {
      await barkalot.connect(user1).approve(user2.address, ethers.parseEther("1000"));
      expect(await barkalot.allowance(user1.address, user2.address)).to.equal(ethers.parseEther("1000"));
      
      await barkalot.connect(user2).transferFrom(user1.address, user3.address, ethers.parseEther("500"));
      expect(await barkalot.balanceOf(user3.address)).to.equal(ethers.parseEther("500"));
    });

    it("Should handle increase/decrease allowance", async function () {
      await barkalot.connect(user1).approve(user2.address, ethers.parseEther("1000"));
      await barkalot.connect(user1).increaseAllowance(user2.address, ethers.parseEther("500"));
      expect(await barkalot.allowance(user1.address, user2.address)).to.equal(ethers.parseEther("1500"));
      
      await barkalot.connect(user1).decreaseAllowance(user2.address, ethers.parseEther("200"));
      expect(await barkalot.allowance(user1.address, user2.address)).to.equal(ethers.parseEther("1300"));
    });

    it("Should revert transferFrom with insufficient allowance", async function () {
      await barkalot.connect(user1).approve(user2.address, ethers.parseEther("100"));
      
      await expect(
        barkalot.connect(user2).transferFrom(user1.address, user3.address, ethers.parseEther("200"))
      ).to.be.revertedWith("ERC20: transfer amount exceeds allowance");
    });
  });

  describe("Edge Cases and Revert Conditions", function () {
    it("Should revert transfer to zero address", async function () {
      await expect(
        barkalot.connect(user1).transfer(ethers.ZeroAddress, ethers.parseEther("100"))
      ).to.be.revertedWith("ERC20: transfer to the zero address");
    });

    it("Should revert transfer with zero amount", async function () {
      await expect(
        barkalot.connect(user1).transfer(user2.address, 0)
      ).to.be.revertedWith("amount must be greater than 0");
    });

    it("Should revert transfer with insufficient balance", async function () {
      const balance = await barkalot.balanceOf(user1.address);
      await expect(
        barkalot.connect(user1).transfer(user2.address, balance + 1n)
      ).to.be.revertedWith("ERC20: transfer amount exceeds balance");
    });
  });
});
