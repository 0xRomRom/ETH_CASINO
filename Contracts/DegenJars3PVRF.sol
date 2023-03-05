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
    mapping(address => bool) public PLAYERS;
    address[3] public PLAYERS_ARRAY;

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

    // For this example, retrieve 1 random values in one request.
    // Cannot exceed VRFV2Wrapper.getConfig().maxNumWords.
    uint32 numWords = 1;

    // Address LINK - hardcoded for Goerli
    address linkAddress = 0x326C977E6efc84E512bB9C30f76E30c160eD06FB;

    // address WRAPPER - hardcoded for Goerli
    address wrapperAddress = 0x708701a1DfF4f478de54383E49a627eD4852C816;

    // Check if VRF call was paid
    uint private requestPaid;

    // GameEvents
    event PlayerJoined(address player, uint timeEntered);
    event PlayerLeft(address player, uint timeLeft);
    event GameWinner(address winner, uint winTimeStamp);

    address public lastGameWinner;

    // Initial contract deposit: 20000000000000000
    constructor() payable VRFV2WrapperConsumerBase(linkAddress, wrapperAddress) {
        BET_AMOUNT = 10000000000000000 wei; //0.01Eth
        WIN_AMOUNT = 28000000000000000 wei; //0.028Eth
        MAX_PLAYER_COUNT = 3;
        PLAYER_COUNT = 0;
        requestPaid = 0;
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

        requestPaid = VRF_V2_WRAPPER.calculateRequestPrice(callbackGasLimit);

        return requestId;
    }

   function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        require(requestPaid > 0, "request not found");
        require(PLAYER_COUNT > 2, "Not enough players");

        requestPaid = 0;

        //Store function param (unused)
        uint reqID;
        reqID = _requestId;

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

        // Announce winner
        emit GameWinner(winnerAddress, block.timestamp);
        lastGameWinner = winnerAddress;

        // Reset game values
        deleteAllPlayers();
        requestPaid = 0;

    }

    /******************/
    /* HELPER FUNCTIONS
    /******************/

    // Helper function that handles adding new player to mapping and array    
    function addPlayer(address _address) private {
        PLAYERS[_address] = true;
        PLAYERS_ARRAY.push(_address);
        emit PlayerJoined(_address, block.timestamp);
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
        emit PlayerLeft(_address, block.timestamp);
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
    function doesUserExist(address _player) public view returns (bool) {
        return PLAYERS[_player] == true;
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
        require(!doesUserExist(msg.sender), 'Already in game');

        // Increase active players 
        PLAYER_COUNT++;

        // Add player to active players list
        addPlayer(msg.sender);

        //Checks if player cap is met => pays winner
        if (PLAYER_COUNT == 3) {
            payWinner();
        }
      
    }

    // Player leaves game and is refunded
    function leaveGame() public {
        // Check if a timestamp of entry was registered
        require(doesUserExist(msg.sender), 'User not in game');

        // Can't leave game that is in progress
        require(PLAYER_COUNT < 3, 'Game concludes soon');

        // Prevents from withdrawing without depositing first
        require(PLAYER_COUNT > 0, 'Cant leave game with no players');

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
        require(address(this).balance >= WIN_AMOUNT, 'Insufficient funsu');

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

    // Withdraw link from contract
    function withdrawLink() public onlyOwner {
        LinkTokenInterface link = LinkTokenInterface(linkAddress);
        require(
            link.transfer(msg.sender, link.balanceOf(address(this))),
            "Unable to transfer"
        );
    }
}

// BET_AMOUNT = 10000000000000000 wei; //0.01Eth