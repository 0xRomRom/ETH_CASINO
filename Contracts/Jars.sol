// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";

contract BetJars is Ownable {

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

    constructor() {
        BET_AMOUNT = 10000000000000000 wei; //0.01Eth
        WIN_AMOUNT = 28000000000000000 wei; //0.028Eth
        MAX_PLAYER_COUNT = 3;
        PLAYER_COUNT = 0;
        DEPLOYOOR = payable(msg.sender);
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
        // Check if player has sufficient funds to enter the game
        require(msg.value >= BET_AMOUNT, 'Pay more ether to enter the game');

        // Check if the player cap has not been exceeded
        require(PLAYER_COUNT < MAX_PLAYER_COUNT, 'Maximum playercount has been reached');

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
        require(address(this).balance >= WIN_AMOUNT, 'Insufficient funsu');

        // Reset player count
        PLAYER_COUNT = 0;

        // Reset mapping and array values
        deleteAllPlayers();

        // Pay winner logic (hardcoded to deployoor for the minute)
        payable(DEPLOYOOR).transfer(WIN_AMOUNT);
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
        payable(msg.sender).transfer(address(this).balance);

        // Reset mapping and array values
        deleteAllPlayers();

    }
}

// BET_AMOUNT = 10000000000000000 wei; //0.01Eth