pragma solidity >0.6.0;
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./IRandomNumberGenerator.sol";
import "./IRandomNumberGenerator.sol";
import "./Testable.sol";
import "./ILotty.sol";
import "hardhat/console.sol";

contract Lotty is Ownable, ReentrancyGuard, Testable {
    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for IERC20;

    IERC20 internal token3rd_;

    //Token in treasury can be added to lottery round
    address public injectorAddress;

    address public operatorAddress;
    address public treasuryAddress;

    uint256 public currentLotteryId;
    uint256 public currentTicketId;

    uint256 public maxNumberTicketsPerBuyOrClaim = 100;

    uint256 public maxPriceTicketIn3rdToken = 50 ether;
    uint256 public minPriceTicketIn3rdToken = 0.05 ether;

    uint256 public pendingInjectionNextLottery;

    uint256 public constant MIN_LENGTH_LOTTERY = 4 hours - 5 minutes; // 4 hours
    uint256 public constant MAX_LENGTH_LOTTERY = 4 days + 5 minutes; // 4 days
    uint256 public constant MAX_TREASURY_FEE = 3000; // 30%

    uint8 public sizeOfLottery_;
    // Max range for numbers (starting at 0)
    uint16 public maxValidRange_;

    mapping(address => mapping(uint256 => uint256[]))
        private _userTicketIdsPerLotteryId;
    mapping(uint256 => mapping(uint32 => uint256))
        private _numberTicketsPerLotteryId;

    IRandomNumberGenerator public randomGenerator;

    enum Status {
        Pending,
        Open,
        Close,
        Claimable
    }
    struct Ticket {
        uint32 number;
        address owner;
    }

    event LotteryStartEvent(
        uint256 indexed lotteryId,
        uint256 startTime,
        uint256 endTime,
        uint256 priceTicketIn3rdToken,
        uint256 injectedAmount
    );
    event BuyTicketEvent(
        address indexed buyer,
        uint256 indexed lotteryId,
        uint256 numberTickets
    );

    struct Lottery {
        Status status;
        uint256 startTime;
        uint256 endTime;
        uint256 priceTicketIn3rdToken;
        //uint256 discountDivisor;
        uint256[6] rewardsBreakdown; // 0: 1 matching number // 5: 6 matching numbers
        uint256 treasuryFee; // 500: 5% // 200: 2% // 50: 0.5%
        uint256[6] usdPerBracket;
        uint256[6] countWinnersPerBracket;
        uint256 firstTicketId;
        uint256 firstTicketIdNextLottery;
        uint256 amountCollectedIn3rdToken;
        uint32 finalNumber;
    }

    // Bracket calculator is used for verifying claims for ticket prizes
    mapping(uint32 => uint32) private _bracketCalculator;
    mapping(uint256 => Lottery) private _lotteries;
    mapping(uint256 => Ticket) private _tickets;

    constructor(address _token3rd, address _timer) public Testable(_timer) {
        require(_token3rd != address(0), "Contracts cannot be 0 address");

        token3rd_ = IERC20(_token3rd);

        // Initializes a mapping
        _bracketCalculator[0] = 1;
        _bracketCalculator[1] = 11;
        _bracketCalculator[2] = 111;
        _bracketCalculator[3] = 1111;
        _bracketCalculator[4] = 11111;
        _bracketCalculator[5] = 111111;
    }

    modifier notContract() {
        require(!_isContract(msg.sender), "Contract not allowed");
        require(msg.sender == tx.origin, "Proxy contract not allowed");
        _;
    }

    modifier onlyOperator() {
        require(msg.sender == operatorAddress, "Not operator");
        _;
    }

    modifier onlyOwnerOrInjector() {
        require(
            (msg.sender == owner()) || (msg.sender == injectorAddress),
            "Not owner or injector"
        );
        _;
    }

    function startLotty(
        uint256 _endTime,
        uint256 _priceBy3rdToken,
        uint256[6] calldata _rewardsBreakdown,
        uint256 _treasuryFee
    ) external onlyOwner {
        console.log("blocktime %s", block.timestamp);
        console.log("min_leng %s", MIN_LENGTH_LOTTERY);
        console.log("max_leng %s", MAX_LENGTH_LOTTERY);
        console.log("dk1 %s", _endTime - block.timestamp);

        require(
            (currentLotteryId == 0) ||
                (_lotteries[currentLotteryId].status == Status.Claimable),
            "Not time to start lottery"
        );

        // require(
        //     ((_endTime - block.timestamp) > MIN_LENGTH_LOTTERY) &&
        //         ((_endTime - block.timestamp) < MAX_LENGTH_LOTTERY),
        //     "Lottery length outside of range"
        // );

        require(
            (_priceBy3rdToken >= minPriceTicketIn3rdToken) &&
                (_priceBy3rdToken <= maxPriceTicketIn3rdToken),
            "Outside of limits"
        );

        // require(_treasuryFee <= MAX_TREASURY_FEE, "Treasury fee too high");

        require(
            (_rewardsBreakdown[0] +
                _rewardsBreakdown[1] +
                _rewardsBreakdown[2] +
                _rewardsBreakdown[3] +
                _rewardsBreakdown[4] +
                _rewardsBreakdown[5]) == 100,
            "Rewards must equal 10000"
        );

        currentLotteryId++;
        //console.log("current lotteryID: %s", currentLotteryId);

        _lotteries[currentLotteryId] = Lottery({
            status: Status.Open,
            startTime: block.timestamp,
            endTime: _endTime,
            priceTicketIn3rdToken: _priceBy3rdToken,
            rewardsBreakdown: _rewardsBreakdown,
            treasuryFee: _treasuryFee,
            usdPerBracket: [
                uint256(0),
                uint256(0),
                uint256(0),
                uint256(0),
                uint256(0),
                uint256(0)
            ],
            countWinnersPerBracket: [
                uint256(0),
                uint256(0),
                uint256(0),
                uint256(0),
                uint256(0),
                uint256(0)
            ],
            firstTicketId: currentTicketId,
            firstTicketIdNextLottery: currentTicketId,
            amountCollectedIn3rdToken: pendingInjectionNextLottery,
            finalNumber: 0
        });

        emit LotteryStartEvent(
            currentLotteryId,
            block.timestamp,
            _endTime,
            _priceBy3rdToken,
            pendingInjectionNextLottery
        );

        pendingInjectionNextLottery = 0;
    }

    function viewCurrentLotteryId() external view returns (uint256) {
        return currentLotteryId;
    }

    function _calculateTotalPriceForBulkTickets(
        uint256 _priceTicket,
        uint256 _numberTickets
    ) internal pure returns (uint256) {
        return (_priceTicket * _numberTickets);
    }

    function buyTickets(uint256 _lotteryId, uint32[] calldata _ticketNumbers)
        external
        notContract
        nonReentrant
    {
        require(_ticketNumbers.length != 0, "No ticket specified");
        require(
            _ticketNumbers.length <= maxNumberTicketsPerBuyOrClaim,
            "Too many tickets"
        );

        require(
            _lotteries[_lotteryId].status == Status.Open,
            "Lottery is not open"
        );
        console.log("block ts %s", block.timestamp);
        console.log("end ts %s", _lotteries[_lotteryId].endTime);

        require(
            block.timestamp < _lotteries[_lotteryId].endTime,
            "Lottery is over"
        );

        // Calculate number of token to this contract
        uint256 amount3rdTokenToTransfer = _calculateTotalPriceForBulkTickets(
            _lotteries[_lotteryId].priceTicketIn3rdToken,
            _ticketNumbers.length
        );

        console.log("amount3rdTokenToTransfer %s", amount3rdTokenToTransfer);

        // Transfer cake tokens to this contract
        token3rd_.safeTransferFrom(
            address(msg.sender),
            address(this),
            amount3rdTokenToTransfer
        );

        // Increment the total amount collected for the lottery round
        _lotteries[_lotteryId]
            .amountCollectedIn3rdToken += amount3rdTokenToTransfer;

        //console.log("_ticketNumbers %s", _ticketNumbers);

        for (uint256 i = 0; i < _ticketNumbers.length; i++) {
            uint32 thisTicketNumber = _ticketNumbers[i];

            console.log("ticket number %s", thisTicketNumber);
            require(
                (thisTicketNumber >= 1000000) && (thisTicketNumber <= 1999999),
                "Outside range"
            );

            _numberTicketsPerLotteryId[_lotteryId][
                1 + (thisTicketNumber % 10)
            ]++;
            _numberTicketsPerLotteryId[_lotteryId][
                11 + (thisTicketNumber % 100)
            ]++;
            _numberTicketsPerLotteryId[_lotteryId][
                111 + (thisTicketNumber % 1000)
            ]++;
            _numberTicketsPerLotteryId[_lotteryId][
                1111 + (thisTicketNumber % 10000)
            ]++;
            _numberTicketsPerLotteryId[_lotteryId][
                11111 + (thisTicketNumber % 100000)
            ]++;
            _numberTicketsPerLotteryId[_lotteryId][
                111111 + (thisTicketNumber % 1000000)
            ]++;

            //console.log(JSON.stringify(_numberTicketsPerLotteryId));

            _userTicketIdsPerLotteryId[msg.sender][_lotteryId].push(
                currentTicketId
            );

            _tickets[currentTicketId] = Ticket({
                number: thisTicketNumber,
                owner: msg.sender
            });

            // Increase lottery ticket number
            currentTicketId++;
        }

        emit BuyTicketEvent(msg.sender, _lotteryId, _ticketNumbers.length);
    }

    /**
     * @notice View lottery information
     * @param _lotteryId: lottery id
     */
    function viewLottery(uint256 _lotteryId)
        external
        view
        returns (Lottery memory)
    {
        return _lotteries[_lotteryId];
    }

    function getCurrentLotteryId() external view returns (uint256) {
        return currentLotteryId;
    }

    function _isContract(address _addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(_addr)
        }
        return size > 0;
    }
}
