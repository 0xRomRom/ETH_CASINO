// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "https://github.com/smartcontractkit/chainlink/blob/develop/contracts/src/v0.8/VRFV2WrapperConsumerBase.sol";

contract BetJars is Ownable, VRFV2WrapperConsumerBase {

    // Same as onlyOwner
    address public DEPLOYOOR;

    // Wager amount
    uint public BET_AMOUNT;

    // Win amount
    uint public WIN_AMOUNT;

    // Max player count
    uint public MAX_PLAYER_COUNT;

    // Active players in Jar
    mapping(address => uint) public PLAYERS;
    address[] public PLAYERS_ARRAY;

    // Current player count
    uint public PLAYER_COUNT;


    // Depends on the number of requested values that you want sent to the
    // fulfillRandomWords() function. Test and adjust
    // this limit based on the network that you select, the size of the request,
    // and the processing of the callback request in the fulfillRandomWords()
    // function.
    uint32 callbackGasLimit = 500000;

    // The default is 3, but you can set this higher.
    uint16 requestConfirmations = 3;

    // For this example, retrieve 2 random values in one request.
    // Cannot exceed VRFV2Wrapper.getConfig().maxNumWords.
    uint32 numWords = 1;

    // Address LINK - hardcoded for Goerli
    address linkAddress = 0x326C977E6efc84E512bB9C30f76E30c160eD06FB;

    // address WRAPPER - hardcoded for Goerli
    address wrapperAddress = 0x708701a1DfF4f478de54383E49a627eD4852C816;

    // Past requests Id.
    uint[] public requestIds;
    uint public lastRequestId;

    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(
        uint256 requestId,
        uint256[] randomWords,
        uint256 payment
    );

    struct RequestStatus {
    uint256 paid; // amount paid in link
    bool fulfilled; // whether the request has been successfully fulfilled
    uint256[] randomWords; // resulting words
    }

    mapping(uint256 => RequestStatus)
        public s_requests; /* requestId --> requestStatus */


    constructor() payable VRFV2WrapperConsumerBase(linkAddress, wrapperAddress) {
        BET_AMOUNT = 10000000000000000 wei; //0.01Eth
        WIN_AMOUNT = 28000000000000000 wei; //0.028Eth
        MAX_PLAYER_COUNT = 3;
        PLAYER_COUNT = 0;
        DEPLOYOOR = payable(msg.sender);
        
    }

    /******************/
    /* VRF Logic
    /******************/

    function requestRandomWords() private
        returns (uint256 requestId)
    {
        requestId = requestRandomness(
            callbackGasLimit,
            requestConfirmations,
            numWords
        );
        s_requests[requestId] = RequestStatus({
            paid: VRF_V2_WRAPPER.calculateRequestPrice(callbackGasLimit),
            randomWords: new uint256[](0),
            fulfilled: false
        });
        requestIds.push(requestId);
        lastRequestId = requestId;
        emit RequestSent(requestId, numWords);
        return requestId;
    }

   function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        require(s_requests[_requestId].paid > 0, "request not found");
        s_requests[_requestId].fulfilled = true;
        s_requests[_requestId].randomWords = _randomWords;
        emit RequestFulfilled(
            _requestId,
            _randomWords,
            s_requests[_requestId].paid
        );

        // Winner info
        uint winnerIndex;
        uint finalWinner;
        address winnerAddress;

        // Winner index and address
        winnerIndex = _randomWords[0];
        finalWinner = winnerIndex % 3;
        winnerAddress = PLAYERS_ARRAY[finalWinner];

        // Pay winner
        payable(winnerAddress).transfer(WIN_AMOUNT);

        // Reset player count
        PLAYER_COUNT = 0;

        // Reset mapping and array values
        deleteAllPlayers();


    }

    /******************/
    /* HELPER FUNCTIONS
    /******************/

    // Helper function that handles adding new player to mapping and array    
    function addPlayer(address _address) private {
        PLAYERS[_address] = block.timestamp;
        PLAYERS_ARRAY.push(_address);
    }

    // Helper function to remove player from the game (clears mapping and array)
    function removePlayer(address _address) private {
    for (uint i = 0; i < PLAYERS_ARRAY.length; i++) {
        if (PLAYERS_ARRAY[i] == _address) {
            if (i != PLAYERS_ARRAY.length - 1) {
                PLAYERS_ARRAY[i] = PLAYERS_ARRAY[PLAYERS_ARRAY.length - 1];
            }
            PLAYERS_ARRAY.pop();
            delete PLAYERS[_address];
            break;
            }
        }
    }

    // Helper function to delete all players from mapping and array
    function deleteAllPlayers() private {
        for (uint i = 0; i < PLAYERS_ARRAY.length; i++) {
            delete PLAYERS[PLAYERS_ARRAY[i]];
            delete PLAYERS_ARRAY[i];
        }
        PLAYER_COUNT = 0;
        PLAYERS_ARRAY = new address[](0);
        
    }

    // Checks if player exists in player mapping
    function doesUserExist(address _player) public view returns (uint) {
        return PLAYERS[_player];
    }

    /******************/
    /* GAME LOGIC
    /******************/

    // Player enters game
    function enterGame() public payable {
        uint CURRENT_PLAYERS_COUNT;
        CURRENT_PLAYERS_COUNT = PLAYER_COUNT;

        // Check if player has sufficient funds to enter the game
        require(msg.value >= BET_AMOUNT, 'Pay more ether to enter the game');

        // Check if the player cap has not been exceeded
        require(CURRENT_PLAYERS_COUNT < MAX_PLAYER_COUNT, 'Maximum playercount has been reached');

        // Check if the player cap has not been exceeded
        require(PLAYERS_ARRAY.length < MAX_PLAYER_COUNT, 'Maximum playercount has been reached');

        // Check if player is already in game
        require(PLAYERS[msg.sender] == 0, 'Already in game');

        // Increase active players 
        PLAYER_COUNT++;

        // Add player to active players list
        addPlayer(msg.sender);

        // Current player count
        uint CURRENT_PLAYER_COUNT;
        CURRENT_PLAYER_COUNT = PLAYER_COUNT;

        //Checks if player cap is met => pays winner
        if (CURRENT_PLAYER_COUNT == 3) {
            payWinner();
        }
      
    }

    // Player leaves game and is refunded
    function leaveGame() public {
        // Check if a timestamp op entry (player join) was registered
        require(doesUserExist(msg.sender) != 0 , 'User not in game');

        // Can't leave if there's no players
        require(PLAYER_COUNT > 0, "Can't leave, there's no players");

        // Decrement player count
        PLAYER_COUNT--;

        // Call helper function to clear mapping and array value
        removePlayer(msg.sender);

        // Refund player
        payable(msg.sender).transfer(BET_AMOUNT);
    }

    // Pays winner of the game and handles state resets
    function payWinner() private {
        require(PLAYER_COUNT == 3, 'Not enough players to payout');
        require(PLAYERS_ARRAY.length == 3, 'Not enough players to payout');
        // require(address(this).balance >= WIN_AMOUNT, 'Insufficient funsu');

        // Pay winner logic
        requestRandomWords();
    }

    //Emergency contract reset, refunds users and withdraws remaining funds
    function emergencyWithdraw() public onlyOwner {
        require(address(this).balance > 0, 'Nothing to withdraw');
        require(msg.sender == DEPLOYOOR, 'Not the owner');

        // Check for amount of participants and refund accordingly
        if (PLAYERS_ARRAY.length == 1) {
            payable(PLAYERS_ARRAY[0]).transfer(BET_AMOUNT);

        } else if (PLAYERS_ARRAY.length == 2) {

            payable(PLAYERS_ARRAY[0]).transfer(BET_AMOUNT);
            payable(PLAYERS_ARRAY[1]).transfer(BET_AMOUNT); 
        }

        // Withdraw remaining contract funds
        payable(DEPLOYOOR).transfer(address(this).balance);

        // Reset mapping and array values
        deleteAllPlayers();

    }
}

// BET_AMOUNT = 10000000000000000 wei; //0.01Eth