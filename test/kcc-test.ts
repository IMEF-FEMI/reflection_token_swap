import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers, network } from "hardhat";
import { Contract } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import BN from "bn.js"




describe("BSC token test", function () {
    const UNISWAPV2_ROUTER = "0xc5f442007e08e3b13C9f95fA22F2a2B9369d7C8C"
    const tokenLiquidityAmount = (1 * 10 ** 6 * 10 ** 9).toString() // 1 million
    const ethLiquidityAmount = 1  // 


    let uniswapV2Router: Contract;
    let reflectionTokenV2Pair: Contract;

    async function datingTokenFixtures() {

        const accounts = await ethers.getSigners()
        const owner = accounts[0]


        uniswapV2Router = await ethers.getContractAt("IUniswapV2Router01", UNISWAPV2_ROUTER)



        const ReflectionToken = await ethers.getContractFactory("ReflectionToken");

        const reflectionToken = await ReflectionToken.connect(owner).deploy(UNISWAPV2_ROUTER, "ReflectionToken", "RFT",);
        await reflectionToken.deployed()

        reflectionTokenV2Pair = await ethers.getContractAt("IUniswapV2Pair", await reflectionToken.uniswapV2Pair())



        const reserveBefore = await reflectionTokenV2Pair.getReserves();
        let tokenReserve = reserveBefore.reserve0
        let ethReserve = reserveBefore.reserve1

        expect(tokenReserve).to.equal(new BN(0))
        expect(ethReserve).to.equal(new BN(0))

        //add liquidity
        await reflectionToken.connect(owner).approve(reflectionToken.address, tokenLiquidityAmount.toString())

        await reflectionToken.connect(owner).addLiquidity(
            tokenLiquidityAmount.toString(), //8 million,
            { value: ethers.utils.parseEther(ethLiquidityAmount.toString()) }
        )

        return { reflectionToken, accounts, uniswapV2Router, reflectionTokenV2Pair, owner }

    }


    describe("Deployment", function () {

        it("Should deploy and add liquidity to uniswap v2", async function () {
            const { reflectionToken, accounts, owner, reflectionTokenV2Pair, } = await datingTokenFixtures();
            console.log("Token deployed at: ", reflectionToken.address);
            console.log("liquidity deployed: ", reflectionTokenV2Pair.address);




            //set wallets
            await reflectionToken.connect(owner).setDevelopmentWallet(1, accounts[0].address)
            await reflectionToken.connect(owner).setStaffWallet(1, accounts[1].address)
            await reflectionToken.connect(owner).setMarketingWallet(1, accounts[2].address)

            await reflectionToken.connect(owner).setDevelopmentWallet(2, accounts[0].address)
            await reflectionToken.connect(owner).setStaffWallet(2, accounts[1].address)
            await reflectionToken.connect(owner).setMarketingWallet(2, accounts[2].address)
            console.log("1111");

            const buyer = accounts[3]

            await owner.sendTransaction({
                to: buyer.address,
                value: ethers.utils.parseEther("0.15"), // Sends exactly 1.0 ether
            });

            let balance = await reflectionToken.balanceOf(buyer.address)
            console.log("token balance of buyer before purchase: ", balance);

            await reflectionToken.connect(buyer).buyTokens({
                value: ethers.utils.parseEther("0.1")
            })


            balance = await reflectionToken.balanceOf(buyer.address)
            console.log("new token balance of buyer: ", balance);

            const devWalletBalance = await reflectionToken.balanceOf(accounts[0].address)
            // const staffBalance = await reflectionToken.balanceOf(accounts[1].address)
            // const marketingBalance = await reflectionToken.balanceOf(accounts[2].address)
            console.log("dev wallet balance: ", devWalletBalance);
            // console.log("staff wallet balance: ", staffBalance.toNumber());
            // console.log("marketing wallet balance: ", marketingBalance.toNumber());
        });

        // it("transfers to wallets without fees ", async () => {
        //     const { reflectionToken, ethWhale, accounts } = await loadFixture(datingTokenFixtures);

        //     //transfer from owner to user
        //     await reflectionToken.connect(ethWhale).transfer(accounts[0].address, tokenLiquidityAmount.toString())
        //     let balance = await reflectionToken.balanceOf(accounts[0].address)

        //     expect(balance).to.equal(new BN(tokenLiquidityAmount))

        //     //transfer from user to user
        //     await reflectionToken.connect(accounts[0]).transfer(accounts[1].address, tokenLiquidityAmount.toString())
        //     balance = await reflectionToken.balanceOf(accounts[1].address)
        //     expect(balance).to.equal(new BN(tokenLiquidityAmount))

        // })

        // it("set fee wallets ", async () => {
        //     const { reflectionToken, ethWhale, accounts } = await loadFixture(datingTokenFixtures);

        //     //set development wallet
        //     const developmentWallet = accounts[0]
        //     await reflectionToken.connect(ethWhale).setDevelopmentWallet(1, developmentWallet.address)
        //     const devWallet = await (await reflectionToken.feeTier(1)).developmentWallet
        //     expect(devWallet).to.be.equal(developmentWallet.address)

        //     //set staff wallet
        //     const staffWallet = accounts[1]
        //     await reflectionToken.connect(ethWhale).setStaffWallet(1, staffWallet.address)
        //     const staffFeeWallet = await (await reflectionToken.feeTier(1)).staffWallet
        //     expect(staffFeeWallet).to.be.equal(staffWallet.address)
        //     //set marketing wallet
        //     const marketingWallet = accounts[2]
        //     await reflectionToken.connect(ethWhale).setMarketingWallet(1, marketingWallet.address)
        //     const marketingFeeWallet = await (await reflectionToken.feeTier(1)).marketingWallet
        //     expect(marketingFeeWallet).to.be.equal(marketingWallet.address)
        //     //set marketing wallet
        // })

        // it("buys tokens and takes buy fee", async () => {
        //     const { reflectionToken, ethWhale, accounts, reflectionTokenV2Pair } = await loadFixture(datingTokenFixtures);
        //     //set wallets
        //     await reflectionToken.connect(ethWhale).setDevelopmentWallet(1, accounts[0].address)
        //     await reflectionToken.connect(ethWhale).setStaffWallet(1, accounts[1].address)
        //     await reflectionToken.connect(ethWhale).setMarketingWallet(1, accounts[2].address)

        //     await reflectionToken.connect(ethWhale).setDevelopmentWallet(2, accounts[0].address)
        //     await reflectionToken.connect(ethWhale).setStaffWallet(2, accounts[1].address)
        //     await reflectionToken.connect(ethWhale).setMarketingWallet(2, accounts[2].address)

        //     const buyer = accounts[3]
        //     await ethWhale.sendTransaction({
        //         to: buyer.address,
        //         value: ethers.utils.parseEther("20000.0"), // Sends exactly 1.0 ether
        //     });
        //     await reflectionToken.connect(buyer).buyTokens({
        //         value: ethers.utils.parseEther("20000")
        //     })

        //     const balance = await reflectionToken.balanceOf(buyer.address)

        //     console.log(balance.toNumber() / 1e9);
        //     const devWalletBalance = await reflectionToken.balanceOf(accounts[0].address)
        //     const staffBalance = await reflectionToken.balanceOf(accounts[1].address)
        //     const marketingBalance = await reflectionToken.balanceOf(accounts[2].address)
        //     console.log(devWalletBalance.toNumber() / 1e9);
        //     console.log(staffBalance.toNumber() / 1e9);
        //     console.log(marketingBalance.toNumber() / 1e9);

        // })
        // it("sells tokens and takes sell fee", async () => {
        //     const { reflectionToken, ethWhale, accounts, reflectionTokenV2Pair } = await loadFixture(datingTokenFixtures);
        //     //set wallets
        //     await reflectionToken.connect(ethWhale).setDevelopmentWallet(1, accounts[0].address)
        //     await reflectionToken.connect(ethWhale).setStaffWallet(1, accounts[1].address)
        //     await reflectionToken.connect(ethWhale).setMarketingWallet(1, accounts[2].address)

        //     await reflectionToken.connect(ethWhale).setDevelopmentWallet(2, accounts[0].address)
        //     await reflectionToken.connect(ethWhale).setStaffWallet(2, accounts[1].address)
        //     await reflectionToken.connect(ethWhale).setMarketingWallet(2, accounts[2].address)

        //     const seller = accounts[3]
        //     const sellAmount = 1000 * 1e9
        //     await ethWhale.sendTransaction({
        //         to: seller.address,
        //         value: ethers.utils.parseEther("1"), // Sends exactly 1.0 ether
        //     });

        //     await reflectionToken.connect(ethWhale).transfer(seller.address, sellAmount.toString())

        //     await reflectionToken.connect(seller).approve(reflectionToken.address, sellAmount.toString())

        //     let balance = await reflectionToken.balanceOf(seller.address)
        //     console.log("seller balance before: ",balance.toNumber() / 1e9);

        //     balance = await ethers.provider.getBalance(seller.address);
        //     console.log("seller eth balance before: ",balance );

        //     await reflectionToken.connect(seller).sellTokens(sellAmount)

        //     balance = await reflectionToken.balanceOf(seller.address)
        //     console.log("seller balance after: ",balance.toNumber() / 1e9);


        //     balance = await ethers.provider.getBalance(seller.address);
        //     console.log("seller eth balance after: ",balance );




        //     const devWalletBalance = await reflectionToken.balanceOf(accounts[0].address)
        //     const staffBalance = await reflectionToken.balanceOf(accounts[1].address)
        //     const marketingBalance = await reflectionToken.balanceOf(accounts[2].address)
        //     console.log("development wallet: ", devWalletBalance.toNumber() / 1e9);
        //     console.log("staff wallet: ",staffBalance.toNumber() / 1e9);
        //     console.log("marketing wallet: ",marketingBalance.toNumber() / 1e9);


        // })
    })
});
