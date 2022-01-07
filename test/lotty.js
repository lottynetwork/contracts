const { expect, assert } = require("chai");
const { network } = require("hardhat");

const {

    lotto,
    BigNumber,
    generateLottoNumbers
} = require("./settings.js");

describe("Lottery contract", function () {
    let mock_erc20Contract;
    // Creating the instance and contract info for the lottery contract
    let lotteryInstance, lotteryContract;
    // Creating the instance and contract info for the lottery NFT contract
    let lotteryNftInstance, lotteryNftContract;
    // Creating the instance and contract info for the cake token contract
    let tokenInstance;
    // Creating the instance and contract info for the timer contract
    let timerInstance, timerContract;
    // Creating the instance and contract info for the mock rand gen
    let randGenInstance, randGenContract;
    // Creating the instance and contract of all the contracts needed to mock
    // the ChainLink contract ecosystem. 
    let linkInstance;
    let mock_vrfCoordInstance, mock_vrfCoordContract;

    // Creating the users
    let owner, buyer;


    beforeEach(async () => {
        // Getting the signers provided by ethers
        const signers = await ethers.getSigners();
        // Creating the active wallets for use
        owner = signers[0];
        buyer = signers[1];

        // Getting the lottery code (abi, bytecode, name)
        lotteryContract = await ethers.getContractFactory("Lotty");
        // Getting the lotteryNFT code (abi, bytecode, name)
        //lotteryNftContract = await ethers.getContractFactory("LotteryNFT");
        // Getting the lotteryNFT code (abi, bytecode, name)
        mock_erc20Contract = await ethers.getContractFactory("Mock_erc20");
        // Getting the timer code (abi, bytecode, name)
        timerContract = await ethers.getContractFactory("Timer");
        // Getting the ChainLink contracts code (abi, bytecode, name)
        randGenContract = await ethers.getContractFactory("RandomNumberGenerator");
        mock_vrfCoordContract = await ethers.getContractFactory("Mock_VRFCoordinator");

        // Deploying the instances
        timerInstance = await timerContract.deploy();
        // console.log(timerInstance);
        tokenInstance = await mock_erc20Contract.deploy(
            lotto.buy.cake,
        );
        linkInstance = await mock_erc20Contract.deploy(
            lotto.buy.cake,
        );
        mock_vrfCoordInstance = await mock_vrfCoordContract.deploy(
            linkInstance.address,
            lotto.chainLink.keyHash,
            lotto.chainLink.fee
        );
        lotteryInstance = await lotteryContract.deploy(
            tokenInstance.address,
            timerInstance.address,
            lotto.setup.sizeOfLottery,
            lotto.setup.maxValidRange
        );
        randGenInstance = await randGenContract.deploy(
            mock_vrfCoordInstance.address,
            linkInstance.address,
            lotteryInstance.address,
            lotto.chainLink.keyHash,
            lotto.chainLink.fee
        );

        // await lotteryInstance.initialize(
        //     lotteryNftInstance.address,
        //     randGenInstance.address
        // );
        // Making sure the lottery has some cake
        await tokenInstance.mint(
            lotteryInstance.address,
            lotto.newLotto.prize
        );
        // Sending link to lottery
        await linkInstance.transfer(
            randGenInstance.address,
            lotto.buy.cake
        );
    });
    describe("Creating a new lottery tests", function () {
        /**
         * Tests that in the nominal case nothing goes wrong
         */
        it("Nominal case", async function () {
            // Getting the current block timestamp
            let currentTime = await lotteryInstance.getCurrentTime();
            // Converting to a BigNumber for manipulation 
            let timeStamp = new BigNumber(currentTime.toString());
            //let endtime = await lotteryInstance.getCurrentTime() + 1000 * 3600;
            // Creating a new lottery

            //console.log("current time %s", timeStamp.toString());
            let endtime = timeStamp.plus("864000");
            //console.log(endtime.toString());
            await expect(
                lotteryInstance.connect(owner).startLotty(
                    endtime.toString(),
                    lotto.newLotto.prize,
                    //lotto.newLotto.discountDivisor,
                    lotto.newLotto.distribution,
                    lotto.newLotto.cost

                )
            ).to.emit(lotteryInstance, lotto.events.new)
            // Checking that emitted event contains correct information
            // .withArgs(
            //     1,
            //     timeStamp.toString(),
            //     endtime.toString(),
            //     0,
            //     0

            // );
        });
    });


    describe("Buying tickets tests", function () {
        /**
         * Creating a lotto for all buying tests to use. Will be a new instance
         * for each lotto. 
         */
        beforeEach(async () => {
            // Getting the current block timestamp
            let currentTime = await lotteryInstance.getCurrentTime();

            // Converting to a BigNumber for manipulation 
            let timeStamp = new BigNumber(currentTime.toString());
            let endtime = timeStamp.plus("7200");
            // Creating a new lottery
            await lotteryInstance.connect(owner).startLotty(
                endtime.toString(),
                lotto.newLotto.prize,
                //lotto.newLotto.discountDivisor,
                lotto.newLotto.distribution,
                lotto.newLotto.cost
            );
        });

        /**
         * Tests cost per ticket is as expected
         */
        it("Batch buying 1 tickets", async function () {
            // Getting the price to buy

            // Generating chosen numbers for buy

            let lotteryID = await lotteryInstance.getCurrentLotteryId();
            let ticketNumbers = generateLottoNumbers({
                numberOfTickets: 1,
                lottoSize: lotto.setup.sizeOfLottery,
                maxRange: lotto.setup.maxValidRange
            });

            console.log("ticket numbers %s", ticketNumbers);
            // Approving lotto to spend cost
            await tokenInstance.connect(owner).approve(
                lotteryInstance.address,
                lotto.newLotto.prize,
            );
            // Batch buying tokens
            console.log("Start buy 1 ticket");
            await lotteryInstance.buyTickets(
                lotteryID,
                [1200000]
            );

            console.log("end buy ticket");
            // Testing results
            assert.equal(
                lotto.newLotto.prize.toString(),
                lotto.buy.one.cost,
                "Incorrect cost for batch buy of 1"
            );
        });

        it("Invalid buying time", async function () {
            // Getting the price to buy
            //let price = 10 * lotto.newLotto.prize;
            // Generating chosen numbers for buy
            let lotteryID = await lotteryInstance.getCurrentLotteryId();

            let ticketNumbers = generateLottoNumbers({
                numberOfTickets: 1,
                lottoSize: lotto.setup.sizeOfLottery,
                maxRange: lotto.setup.maxValidRange
            });
            // Approving lotto to spend cost
            await tokenInstance.connect(owner).approve(
                lotteryInstance.address,
                lotto.newLotto.prize
            );
            // Getting the current block timestamp
            let currentTime = await lotteryInstance.getCurrentTime();
            //console.log('currenttime %s', new Date(currentTime * 1000));
            // Converting to a BigNumber for manipulation 
            let timeStamp = new BigNumber(currentTime.toString());
            // Getting the timestamp for invalid time for buying
            let futureTime = timeStamp.plus("10000");
            // Setting the time forward 
            //await lotteryInstance.setCurrentTime(futureTime.toString());

            //let newcurrentTime = await lotteryInstance.getCurrentTime();
            //console.log('newcurrenttime %s', new Date(newcurrentTime * 1000));
            //let lottery = await lotteryInstance.viewLottery(lotteryID);
            // console.log(lottery);
            //console.log("end time %s", new Date(lottery.endTime * 1000));

            // Batch buying tokens
            // await expect(
            //     lotteryInstance.connect(owner).buyTickets(
            //         lotteryID,
            //         [1200000]
            //     )
            // ).to.be.revertedWith("Lottery is over");
        });

    });

});