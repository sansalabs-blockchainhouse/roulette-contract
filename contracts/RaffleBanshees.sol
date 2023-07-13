// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RaffleBanshees is VRFConsumerBaseV2, ConfirmedOwner, ReentrancyGuard {
    IERC20 public erc20Token;
    address payable public funds;
    enum RaffleState {
        Open,
        Calculating,
        Closed
    }

    enum RaffleType {
        Normal,
        Token
    }

    event RequestSent(uint256 requestId, uint32 numWords);

    struct Raffle {
        address creator;
        IERC721 nftContract;
        uint256 nftId;
        string name;
        string image;
        uint256 ticketPrice;
        uint256 ticketsBought;
        RaffleState raffleState;
        RaffleType raffleType;
        address[] tickets;
        uint256 startDate;
        uint256 endDate;
        address winner;
    }

    Raffle[] public raffles;

    struct RaffleStatus {
        uint256 randomWord;
        bool fulfilled;
        address winner;
        uint256 raffleId;
    }

    mapping(uint256 => RaffleStatus) public statuses;
    mapping(uint256 => uint256[]) public raffleTickets; // Mapeamento de raffleId para os tickets correspondentes

    // past requests Id.
    uint256[] public requestIds;
    uint256 public lastRequestId;

    uint256 public lastTimeStamp;

    address payable[] public players;

    event RaffleEnter(address indexed player);
    event RequestRaffleWinner(uint256 indexed requestId);
    event WinnerPicked(address indexed player);
    event TicketPurchased(
        uint256 indexed ticketId,
        uint256 indexed raffleId,
        address indexed buyer,
        uint256 ticketCount
    );

    VRFCoordinatorV2Interface COORDINATOR;

    uint64 s_subscriptionId;

    bytes32 keyHash =
        0xd729dc84e21ae57ffb6be0053bf2b0668aa2aaf300a2a7b2ddf7dc0bb6e875a8;

    uint32 callbackGasLimit = 2_000_000;

    uint16 requestConfirmations = 3;

    uint32 numWords = 1;

    constructor(
        uint64 subscriptionId,
        address _erc20Token,
        address payable _funds
    )
        VRFConsumerBaseV2(0xAE975071Be8F8eE67addBC1A82488F1C24858067)
        ConfirmedOwner(msg.sender)
    {
        COORDINATOR = VRFCoordinatorV2Interface(
            0xAE975071Be8F8eE67addBC1A82488F1C24858067
        );
        s_subscriptionId = subscriptionId;
        erc20Token = IERC20(_erc20Token);
        funds = _funds;
    }

    function createRaffle(
        address _nftContract,
        uint256 _nftId,
        uint256 _ticketPrice,
        string memory _name,
        string memory _image,
        uint256 _startDate,
        uint256 _endDate,
        RaffleType _raffleType
    ) external nonReentrant {
        require(_nftContract != address(0), "Invalid NFT contract address");

        IERC721 nftContract = IERC721(_nftContract);
        require(
            nftContract.ownerOf(_nftId) == msg.sender,
            "You are not the owner of NFT"
        );

        nftContract.transferFrom(msg.sender, address(this), _nftId);

        raffles.push(
            Raffle(
                msg.sender,
                nftContract,
                _nftId,
                string(abi.encodePacked(_name)),
                string(abi.encodePacked(_image)),
                _ticketPrice,
                0,
                RaffleState.Open,
                _raffleType,
                new address[](0),
                _startDate,
                _endDate,
                address(0)
            )
        );
    }

    function enterRaffle(uint256 _raffleId, uint256 _ticketCount)
        external
        payable
        nonReentrant
    {
        require(_raffleId < raffles.length, "Invalid raffle ID");
        require(_ticketCount > 0, "Invalid ticket count");

        Raffle storage raffle = raffles[_raffleId];

        uint256 totalPrice = raffle.ticketPrice * _ticketCount;
        require(msg.value >= totalPrice, "Insufficient payment");

        require(raffle.raffleState == RaffleState.Open, "Raffle not open");
        require(block.timestamp >= raffle.startDate, "Raffle not started yet");
        require(block.timestamp <= raffle.endDate, "Raffle has ended");

        funds.transfer(totalPrice);

        for (uint256 i = 0; i < _ticketCount; i++) {
            raffle.tickets.push(msg.sender);
            raffle.ticketsBought++;
        }

        emit TicketPurchased(
            raffle.tickets.length - 1,
            _raffleId,
            msg.sender,
            _ticketCount
        );
    }

    function enterRaffleErc20(uint256 _raffleId, uint256 _ticketCount)
        external
        nonReentrant
    {
        require(_raffleId < raffles.length, "Invalid raffle ID");
        require(_ticketCount > 0, "Invalid ticket count");

        Raffle storage raffle = raffles[_raffleId];

        uint256 totalPrice = raffle.ticketPrice * _ticketCount;
        require(
            erc20Token.balanceOf(msg.sender) >= totalPrice,
            "Insufficient token balance"
        );

        erc20Token.transferFrom(msg.sender, funds, totalPrice);

        require(raffle.raffleState == RaffleState.Open, "Raffle not open");
        require(block.timestamp >= raffle.startDate, "Raffle not started yet");
        require(block.timestamp <= raffle.endDate, "Raffle has ended");

        for (uint256 i = 0; i < _ticketCount; i++) {
            raffle.tickets.push(msg.sender);
            raffle.ticketsBought++;
        }

        emit TicketPurchased(
            raffle.tickets.length - 1,
            _raffleId,
            msg.sender,
            _ticketCount
        );
    }

    function pickWinner(uint256 _raffleId) public onlyOwner returns (uint256) {
        require(_raffleId < raffles.length, "Invalid raffle ID");

        Raffle storage raffle = raffles[_raffleId];

        require(raffle.raffleState == RaffleState.Open, "Raffle not open");

        raffle.raffleState = RaffleState.Calculating;

        uint256 requestId = requestRandomWords();

        statuses[requestId] = RaffleStatus({
            randomWord: 0,
            fulfilled: false,
            winner: address(0),
            raffleId: _raffleId
        });

        return requestId;
    }

    function requestRandomWords() internal returns (uint256 requestId) {
        requestId = COORDINATOR.requestRandomWords(
            keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
        requestIds.push(requestId);
        lastRequestId = requestId;

        emit RequestSent(requestId, numWords);
        return requestId;
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        uint256 raffleId = statuses[_requestId].raffleId;

        Raffle storage raffle = raffles[raffleId];

        require(
            raffle.raffleState == RaffleState.Calculating,
            "Raffle not calc"
        );

        raffle.raffleState = RaffleState.Closed;
        statuses[_requestId].fulfilled = true;

        uint256 indexOfWinner = _randomWords[0] % raffle.tickets.length;
        address recentWinner = raffle.tickets[indexOfWinner];
        raffle.winner = recentWinner;

        statuses[_requestId].winner = recentWinner;

        raffle.nftContract.safeTransferFrom(
            address(this),
            recentWinner,
            raffle.nftId
        );
        emit WinnerPicked(recentWinner);
    }

    function getAllRaffles() external view returns (Raffle[] memory) {
        uint256 raffleCount = raffles.length;
        Raffle[] memory allRaffles = new Raffle[](raffleCount);

        for (uint256 i = 0; i < raffleCount; i++) {
            Raffle storage raffle = raffles[i];
            allRaffles[i] = Raffle(
                raffle.creator,
                raffle.nftContract,
                raffle.nftId,
                raffle.name,
                raffle.image,
                raffle.ticketPrice,
                raffle.ticketsBought,
                raffle.raffleState,
                raffle.raffleType,
                raffle.tickets,
                raffle.startDate,
                raffle.endDate,
                raffle.winner
            );
        }

        return allRaffles;
    }

    function getRaffleById(uint256 _raffleId)
        external
        view
        returns (Raffle memory)
    {
        require(_raffleId < raffles.length, "Invalid raffle ID");

        Raffle storage raffle = raffles[_raffleId];
        Raffle memory raffleWithTickets = Raffle(
            raffle.creator,
            raffle.nftContract,
            raffle.nftId,
            raffle.name,
            raffle.image,
            raffle.ticketPrice,
            raffle.ticketsBought,
            raffle.raffleState,
            raffle.raffleType,
            raffle.tickets,
            raffle.startDate,
            raffle.endDate,
            raffle.winner
        );

        return raffleWithTickets;
    }
}
