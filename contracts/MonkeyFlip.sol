// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MonkeyFlip is VRFConsumerBaseV2, ConfirmedOwner, ReentrancyGuard {
    bool public isActive;

    event RequestSent(uint256 requestId, uint32 numWords);
    event FlipRequest(uint256 requestId);
    event FlipResult(
        uint256 requestId,
        bool didWin,
        FlipSelection choice,
        FlipSelection result,
        address player
    );

    enum FlipSelection {
        HEADS,
        TAILS
    }

    struct FlipStatus {
        uint256 randomWord;
        address player;
        bool didWin;
        bool fulfilled;
        FlipSelection choice;
        uint256 entry;
    }

    struct Game {
        address player;
        bool didWin;
        FlipSelection result;
        FlipSelection choice;
        uint256 datetime;
        uint256 entry;
    }

    Game[] public games;

    mapping(uint256 => FlipStatus) public statuses;

    VRFCoordinatorV2Interface COORDINATOR;

    // Your subscription ID.
    uint64 s_subscriptionId;

    // past requests Id.
    uint256[] public requestIds;
    uint256 public lastRequestId;

    bytes32 keyHash =
        0xd729dc84e21ae57ffb6be0053bf2b0668aa2aaf300a2a7b2ddf7dc0bb6e875a8;

    uint32 callbackGasLimit = 2_000_000;

    uint16 requestConfirmations = 3;

    uint32 numWords = 1;

    constructor(uint64 subscriptionId)
        payable
        VRFConsumerBaseV2(0xAE975071Be8F8eE67addBC1A82488F1C24858067)
        ConfirmedOwner(msg.sender)
    {
        COORDINATOR = VRFCoordinatorV2Interface(
            0xAE975071Be8F8eE67addBC1A82488F1C24858067
        );
        s_subscriptionId = subscriptionId;
        isActive = true;
    }

    function flip(FlipSelection choice)
        external
        payable
        nonReentrant
        returns (uint256)
    {
        require(isActive, "Disabled");
        require(msg.value > 0, "You dont have funds");
        require(
            msg.value >= 1 ether && msg.value <= 20 ether,
            "Invalid bet amount"
        );

        uint256 requestId = requestRandomWords();

        statuses[requestId] = FlipStatus({
            randomWord: 0,
            player: msg.sender,
            didWin: false,
            fulfilled: false,
            choice: choice,
            entry: msg.value
        });

        emit FlipRequest(requestId);

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
        statuses[_requestId].fulfilled = true;

        FlipSelection result = FlipSelection.HEADS;

        if (_randomWords[0] % 2 == 0) {
            result = FlipSelection.TAILS;
        }

        if (result == statuses[_requestId].choice) {
            statuses[_requestId].didWin = true;
            payable(statuses[_requestId].player).transfer(
                statuses[_requestId].entry * 2
            );
        }

        Game memory newGame = Game(
            statuses[_requestId].player,
            statuses[_requestId].didWin,
            result,
            statuses[_requestId].choice,
            block.timestamp * 1000,
            statuses[_requestId].entry
        );

        games.push(newGame);

        emit FlipResult(
            _requestId,
            statuses[_requestId].didWin,
            statuses[_requestId].choice,
            result,
            statuses[_requestId].player
        );
    }

    function getFliptatus(uint256 requestId)
        public
        view
        returns (FlipStatus memory)
    {
        return statuses[requestId];
    }

    function toggleActive() public onlyOwner {
        isActive = !isActive;
    }

    function deposit() public payable nonReentrant onlyOwner {
        uint256 amount = msg.value;
        require(amount > 0, "need greater than 0");
    }

    function withdraw(uint256 amount) public nonReentrant onlyOwner {
        payable(msg.sender).transfer(amount);
    }

    function getAllGames() public view returns (Game[] memory) {
        return games;
    }
}
