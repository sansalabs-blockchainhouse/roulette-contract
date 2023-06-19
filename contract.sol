// SPDX-License-Identifier: MIT
// An example of a consumer contract that relies on a subscription for funding.
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";

/*
    Depending on the BetType, number will be:
      color: 0 for black, 1 for red
      row: 0 for top, 1 for middle, 2 for bottom
      dozen: 0 for first, 1 for second, 2 for third
      eighteen: 0 for low, 1 for high
      modulus: 0 for even, 1 for odd
      number: number
*/

contract Roulette is VRFConsumerBaseV2, ConfirmedOwner {
    uint8[] payouts = [2, 3, 3, 2, 2, 36];
    uint256[] public entrys;

    bool public isActive;

    event RequestSent(uint256 requestId, uint32 numWords);
    event SpinRequest(uint256 requestId);
    event SpinResult(
        uint256 requestId,
        bool didWin,
        uint256 choice,
        uint256 result,
        address player
    );

    event SpinResultOracle(
        bool didWin,
        uint256 choice,
        uint256 result,
        address player
    );

    struct SpinStatus {
        uint256 randomWord;
        address player;
        bool didWin;
        bool fulfilled;
        BetType betType;
        uint256 choice;
        uint256 entry;
    }

    struct Game {
        address player;
        bool didWin;
        uint256 result;
        BetType betType;
        uint256 choice;
        uint256 datetime;
    }

    Game[] public games;

    enum BetType {
        COLOR,
        ROW,
        DOZEN,
        EIGHTEEN,
        MODULUS,
        NUMBER
    }

    mapping(uint256 => SpinStatus) public statuses;

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

    function spinOracle(uint256 choice, BetType betType) external payable {
        require(!isActive, "Disabled");
        require(msg.value > 0, "You dont have funds");
        require(isValidValue(msg.value), "Invalid bet");
        require(choice >= 0 && choice <= 36, "Number is not between 0 and 36");
        uint256 seed = uint256(
            keccak256(
                abi.encodePacked(
                    block.timestamp,
                    block.difficulty,
                    block.number
                )
            )
        );
        uint256 randomNumber = uint256(
            keccak256(
                abi.encodePacked(seed, msg.sender, blockhash(block.number - 1))
            )
        );

        uint256 result = randomNumber % 37;

        bool didWin = false;

        if (result == 0) {
            didWin = betType == BetType.NUMBER && choice == 0;
        } else if (betType == BetType.NUMBER) {
            didWin = (choice == result);
        } else if (betType == BetType.COLOR) {
            if (choice == 0) {
                if (result <= 10 || (result >= 20 && result <= 28)) {
                    didWin = (result % 2 == 0);
                } else {
                    didWin = (result % 2 == 1) && (result != 19);
                }
            } else {
                if (result <= 10 || (result >= 20 && result <= 28)) {
                    didWin = (result % 2 == 1);
                } else {
                    didWin = (result % 2 == 0) || (result == 19);
                }
            }
        } else if (betType == BetType.MODULUS) {
            didWin =
                (choice == 0 && result % 2 == 0) ||
                (choice == 1 && result % 2 == 1);
        } else if (betType == BetType.EIGHTEEN) {
            didWin =
                (choice == 0 && result <= 18) ||
                (choice == 1 && result >= 19);
        } else if (betType == BetType.DOZEN) {
            didWin =
                (choice == 0 && result <= 12) ||
                (choice == 1 && result > 12 && result <= 24) ||
                (choice == 2 && result > 24);
        } else if (betType == BetType.ROW) {
            didWin =
                (choice == 0 && result % 3 == 0) ||
                (choice == 1 && result % 3 == 2) ||
                (choice == 2 && result % 3 == 1);
        }

        if (didWin) {
            payable(msg.sender).transfer(msg.value * payouts[uint256(betType)]);
        }

        Game memory newGame = Game(
            msg.sender,
            didWin,
            result,
            betType,
            choice,
            block.timestamp * 1000
        );

        games.push(newGame);

        emit SpinResultOracle(didWin, choice, result, msg.sender);
    }

    function spin(uint256 choice, BetType betType)
        external
        payable
        returns (uint256)
    {
        require(isActive, "Disabled");
        require(choice >= 0 && choice <= 36, "Number is not between 0 and 36");
        require(msg.value > 0, "You dont have funds");
        require(isValidValue(msg.value), "Invalid bet");
        uint256 requestId = requestRandomWords();

        statuses[requestId] = SpinStatus({
            randomWord: 0,
            player: msg.sender,
            didWin: false,
            fulfilled: false,
            choice: choice,
            betType: betType,
            entry: msg.value
        });

        emit SpinRequest(requestId);

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
        uint256 result = _randomWords[0] % 37;
        statuses[_requestId].fulfilled = true;

        if (result == 0) {
            statuses[_requestId].didWin = (statuses[_requestId].betType ==
                BetType.NUMBER &&
                statuses[_requestId].choice == 0);
            statuses[_requestId].fulfilled = true;
        } else {
            if (statuses[_requestId].betType == BetType.NUMBER) {
                statuses[_requestId].didWin = (statuses[_requestId].choice ==
                    result); /* bet on number */
            } else if (statuses[_requestId].betType == BetType.COLOR) {
                if (statuses[_requestId].choice == 0) {
                    if (result <= 10 || (result >= 20 && result <= 28)) {
                        statuses[_requestId].didWin = (result % 2 == 0) && (result != 19);
                    } else {
                        statuses[_requestId].didWin = (result % 2 == 1);
                    }
                } else {
                    if (result <= 10 || (result >= 20 && result <= 28)) {
                        statuses[_requestId].didWin = (result % 2 == 1);
                    } else {
                        statuses[_requestId].didWin = (result % 2 == 0) || (result == 19);
                    }
                }
            } else if (statuses[_requestId].betType == BetType.MODULUS) {
                if (statuses[_requestId].choice == 0)
                    statuses[_requestId].didWin = (result % 2 == 0); /* bet on even */
                if (statuses[_requestId].choice == 1)
                    statuses[_requestId].didWin = (result % 2 == 1); /* bet on odd */
            } else if (statuses[_requestId].betType == BetType.EIGHTEEN) {
                if (statuses[_requestId].choice == 0)
                    statuses[_requestId].didWin = (result <= 18); /* bet on low 18s */
                if (statuses[_requestId].choice == 1)
                    statuses[_requestId].didWin = (result >= 19); /* bet on high 18s */
            } else if (statuses[_requestId].betType == BetType.DOZEN) {
                if (statuses[_requestId].choice == 0)
                    statuses[_requestId].didWin = (result <= 12); /* bet on 1st dozen */
                if (statuses[_requestId].choice == 1)
                    statuses[_requestId].didWin = (result > 12 && result <= 24); /* bet on 2nd dozen */
                if (statuses[_requestId].choice == 2)
                    statuses[_requestId].didWin = (result > 24); /* bet on 3rd dozen */
            } else if (statuses[_requestId].betType == BetType.ROW) {
                if (statuses[_requestId].choice == 0)
                    statuses[_requestId].didWin = (result % 3 == 0); /* bet on top row */
                if (statuses[_requestId].choice == 1)
                    statuses[_requestId].didWin = (result % 3 == 2); /* bet on middle row */
                if (statuses[_requestId].choice == 2)
                    statuses[_requestId].didWin = (result % 3 == 1); /* bet on bottom row */
            }
        }

        if (statuses[_requestId].didWin) {
            payable(statuses[_requestId].player).transfer(
                statuses[_requestId].entry *
                    payouts[uint256(statuses[_requestId].betType)]
            );
        }

        Game memory newGame = Game(
            statuses[_requestId].player,
            statuses[_requestId].didWin,
            result,
            statuses[_requestId].betType,
            statuses[_requestId].choice,
            block.timestamp * 1000
        );

        games.push(newGame);

        emit SpinResult(
            _requestId,
            statuses[_requestId].didWin,
            statuses[_requestId].choice,
            result,
            statuses[_requestId].player
        );
    }

    function getSpinStatus(uint256 requestId)
        public
        view
        returns (SpinStatus memory)
    {
        return statuses[requestId];
    }

    function toggleActive() public onlyOwner {
        isActive = !isActive;
    }

    function isValidValue(uint256 value) internal view returns (bool) {
        for (uint256 i = 0; i < entrys.length; i++) {
            if (entrys[i] == value) {
                return true;
            }
        }
        return false;
    }

    function addValue(uint256 value) public onlyOwner {
        entrys.push(value);
    }

    function removeValue(uint256 value) public onlyOwner {
        for (uint256 i = 0; i < entrys.length; i++) {
            if (entrys[i] == value) {
                delete entrys[i];
                break;
            }
        }
    }

    function deposit() public payable onlyOwner {
        uint256 amount = msg.value;
        require(amount > 0, "need greater than 0");
    }

    function withdraw(uint256 amount) public onlyOwner {
        payable(msg.sender).transfer(amount);
    }

    function getAllGames() public view returns (Game[] memory) {
        return games;
    }
}
