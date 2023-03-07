import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers, network } from "hardhat";
import { Contract } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import BN from "bn.js"


const WETH = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
const ETH_WHALE = "0xBE0eB53F46cd790Cd13851d5EFf43D12404d33E8"
const WETH_WHALE = "0x8EB8a3b98659Cce290402893d0123abb75E3ab28"
const UNISWAPV2_ROUTER = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D"

describe("Dating token", function () {
    const tokenLiquidityAmount = (1 * 10 ** 6 * 10 ** 9).toString() // 1 million
    const ethLiquidityAmount = 5e5  // 500_000

    let weth: Contract;
    let uniswapV2Router: Contract;
    let reflectionTokenV2Pair: Contract;
    let wethWhale: SignerWithAddress;
    let ethWhale: SignerWithAddress;

    async function datingTokenFixtures() {

        weth = await ethers.getContractAt("IWETH", WETH)
        uniswapV2Router = await ethers.getContractAt("IUniswapV2Router01", UNISWAPV2_ROUTER)

        await network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [WETH_WHALE]
        })
        await network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [ETH_WHALE]
        })
        wethWhale = await ethers.getSigner(WETH_WHALE)
        ethWhale = await ethers.getSigner(ETH_WHALE)

        const accounts = await ethers.getSigners()

        const deploymentBalBefore = await ethers.provider.getBalance(ethWhale.address)
        
        const ReflectionToken = await ethers.getContractFactory("ReflectionToken");
        const reflectionToken = await ReflectionToken.connect(ethWhale).deploy(UNISWAPV2_ROUTER, "ReflectionToken", "RFT", {
            gasLimit: ethers.BigNumber.from(`30000000`),
        });
        await reflectionToken.deployed()
        reflectionTokenV2Pair = await ethers.getContractAt("IUniswapV2Pair", await reflectionToken.uniswapV2Pair())

        const deploymentBalAfter = await ethers.provider.getBalance(ethWhale.address)
        const fee = deploymentBalBefore.sub(deploymentBalAfter)
        console.log("Deployment Fee : ",fee);



        const reserveBefore = await reflectionTokenV2Pair.getReserves();
        let tokenReserve = reserveBefore.reserve0
        let ethReserve = reserveBefore.reserve1

        expect(tokenReserve).to.equal(new BN(0))
        expect(ethReserve).to.equal(new BN(0))

        //add liquidity
        await reflectionToken.connect(ethWhale).approve(reflectionToken.address, tokenLiquidityAmount.toString())

        await reflectionToken.connect(ethWhale).addLiquidity(
            tokenLiquidityAmount.toString(), //8 million,
            { value: ethers.utils.parseEther(ethLiquidityAmount.toString()) }
        )

        return { reflectionToken, accounts, weth, uniswapV2Router, wethWhale, ethWhale, reflectionTokenV2Pair, }
    }


    describe("Deployment", function () {
        it("Should deploy and add liquidity to uniswap v2", async function () {
            const { reflectionToken, ethWhale, reflectionTokenV2Pair } = await loadFixture(datingTokenFixtures);


            expect(await reflectionToken.owner()).to.be.equal(ethWhale.address)

            const reserve = await reflectionTokenV2Pair.getReserves();
            let tokenReserve = reserve.reserve0
            let ethReserve = reserve.reserve1

            expect(tokenReserve).to.equal(new BN(tokenLiquidityAmount))
            expect(ethReserve).to.equal(ethers.utils.parseEther(ethLiquidityAmount.toString()))

        });

        it("transfers to wallets without fees ", async () => {
            const { reflectionToken, ethWhale, accounts } = await loadFixture(datingTokenFixtures);

            //transfer from owner to user
            await reflectionToken.connect(ethWhale).transfer(accounts[0].address, tokenLiquidityAmount.toString())
            let balance = await reflectionToken.balanceOf(accounts[0].address)

            expect(balance).to.equal(new BN(tokenLiquidityAmount))

            //transfer from user to user
            await reflectionToken.connect(accounts[0]).transfer(accounts[1].address, tokenLiquidityAmount.toString())
            balance = await reflectionToken.balanceOf(accounts[1].address)
            expect(balance).to.equal(new BN(tokenLiquidityAmount))

        })

        it("set fee wallets ", async () => {
            const { reflectionToken, ethWhale, accounts } = await loadFixture(datingTokenFixtures);
            const buyTier = 1
            //set development wallet
            const developmentWallet = accounts[0]
            await reflectionToken.connect(ethWhale).setDevelopmentWallet(buyTier, developmentWallet.address)
            const devWallet = await (await reflectionToken.feeTier(buyTier)).developmentWallet
            expect(devWallet).to.be.equal(developmentWallet.address)

            //set staff wallet
            const staffWallet = accounts[1]
            await reflectionToken.connect(ethWhale).setStaffWallet(1, staffWallet.address)
            const staffFeeWallet = await (await reflectionToken.feeTier(1)).staffWallet
            expect(staffFeeWallet).to.be.equal(staffWallet.address)
            //set marketing wallet
            const marketingWallet = accounts[2]
            await reflectionToken.connect(ethWhale).setMarketingWallet(1, marketingWallet.address)
            const marketingFeeWallet = await (await reflectionToken.feeTier(1)).marketingWallet
            expect(marketingFeeWallet).to.be.equal(marketingWallet.address)
            //set marketing wallet
        })

        it("buys tokens and takes buy fee", async () => {
            const { reflectionToken, ethWhale, accounts, reflectionTokenV2Pair } = await loadFixture(datingTokenFixtures);
            //set wallets
            await reflectionToken.connect(ethWhale).setDevelopmentWallet(1, accounts[0].address)
            await reflectionToken.connect(ethWhale).setStaffWallet(1, accounts[1].address)
            await reflectionToken.connect(ethWhale).setMarketingWallet(1, accounts[2].address)

            await reflectionToken.connect(ethWhale).setDevelopmentWallet(2, accounts[0].address)
            await reflectionToken.connect(ethWhale).setStaffWallet(2, accounts[1].address)
            await reflectionToken.connect(ethWhale).setMarketingWallet(2, accounts[2].address)

            const buyer = accounts[3]
            const reflectionWatcher = accounts[4]

            const monitorAmount = 1000 * 1e9
            await reflectionToken.connect(ethWhale).transfer(reflectionWatcher.address, monitorAmount.toString())
            let reflectionWatcherBal = await reflectionToken.balanceOf(reflectionWatcher.address)
            console.log("reflectionWatcherBal before: ", reflectionWatcherBal)



            await ethWhale.sendTransaction({
                to: buyer.address,
                value: ethers.utils.parseEther("20000.0"), // Sends exactly 1.0 ether
            });
            await reflectionToken.connect(buyer).buyTokens({
                value: ethers.utils.parseEther("20000")
            })

            const balance = await reflectionToken.balanceOf(buyer.address)

            console.log("new token balance of buyer: ",balance.toNumber() / 1e9);
            const devWalletBalance = await reflectionToken.balanceOf(accounts[0].address)
            const staffBalance = await reflectionToken.balanceOf(accounts[1].address)
            const marketingBalance = await reflectionToken.balanceOf(accounts[2].address)
             reflectionWatcherBal = await reflectionToken.balanceOf(reflectionWatcher.address)



            console.log("new token Balance of development wallet: ",devWalletBalance.toNumber() / 1e9);
            console.log("new token Balance of staff wallet: ",staffBalance.toNumber() / 1e9);
            console.log("new token Balance of marketing wallet: ",marketingBalance.toNumber() / 1e9);

            console.log("new reflectionWatch Balance: ",reflectionWatcherBal.toNumber() );

        })

        it("sells tokens and takes sell fee", async () => {
            const { reflectionToken, ethWhale, accounts, reflectionTokenV2Pair } = await loadFixture(datingTokenFixtures);
            //set wallets
            await reflectionToken.connect(ethWhale).setDevelopmentWallet(1, accounts[0].address)
            await reflectionToken.connect(ethWhale).setStaffWallet(1, accounts[1].address)
            await reflectionToken.connect(ethWhale).setMarketingWallet(1, accounts[2].address)

            await reflectionToken.connect(ethWhale).setDevelopmentWallet(2, accounts[0].address)
            await reflectionToken.connect(ethWhale).setStaffWallet(2, accounts[1].address)
            await reflectionToken.connect(ethWhale).setMarketingWallet(2, accounts[2].address)

            const seller = accounts[3]
            const sellAmount = 1000 * 1e9
            await ethWhale.sendTransaction({
                to: seller.address,
                value: ethers.utils.parseEther("1"), // Sends exactly 1.0 ether
            });

            await reflectionToken.connect(ethWhale).transfer(seller.address, sellAmount.toString())

            await reflectionToken.connect(seller).approve(reflectionToken.address, sellAmount.toString())

            let balance = await reflectionToken.balanceOf(seller.address)
            console.log("seller balance before: ",balance.toNumber() / 1e9);

            balance = await ethers.provider.getBalance(seller.address);
            console.log("seller eth balance before: ",balance );

            await reflectionToken.connect(seller).sellTokens(sellAmount)

            balance = await reflectionToken.balanceOf(seller.address)
            console.log("seller balance after: ",balance.toNumber() / 1e9);

            
            balance = await ethers.provider.getBalance(seller.address);
            console.log("seller eth balance after: ",balance );

            


            const devWalletBalance = await reflectionToken.balanceOf(accounts[0].address)
            const staffBalance = await reflectionToken.balanceOf(accounts[1].address)
            const marketingBalance = await reflectionToken.balanceOf(accounts[2].address)
            console.log("development wallet: ", devWalletBalance.toNumber() / 1e9);
            console.log("staff wallet: ",staffBalance.toNumber() / 1e9);
            console.log("marketing wallet: ",marketingBalance.toNumber() / 1e9);

            
        })
    })
});
