// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

import "./TimeUnit.sol";
import "./CommitReveal.sol";

contract RPS {
    // ใช้ Commit-Reveal Scheme แยกของผู้เล่น 2 คน
    CommitReveal private commitRevealp0 = new CommitReveal();
    CommitReveal private commitRevealp1 = new CommitReveal();
    
    // ใช้ TimeUnit เพื่อตรวจจับเวลาในการขอ Refund
    TimeUnit private timeUnit = new TimeUnit();
    
    uint public numPlayer = 0; // จำนวนผู้เล่นที่เข้าร่วมเกม
    uint public reward = 0; // รางวัลสะสมในเกม
    
    mapping(address => uint) private player_choice; // ตัวเลือกของผู้เล่น (0-4)
    mapping(address => bool) private player_not_commit; // ตรวจสอบว่าผู้เล่น Commit แล้วหรือยัง
    mapping(address => bool) private player_not_reveal; // ตรวจสอบว่าผู้เล่น Reveal แล้วหรือยัง
    mapping(address => bytes32) private player_originhash; // เก็บค่า Hash ของผู้เล่น
    
    address[] public players; // รายชื่อผู้เล่นที่เข้าร่วมเกม
    uint public numCommit = 0; // จำนวนผู้เล่นที่ Commit แล้ว
    uint public numReveal = 0; // จำนวนผู้เล่นที่ Reveal แล้ว

    // กำหนด Address ที่อนุญาตให้เล่น (Whitelisted)
    address[4] private allowedAccounts = [
        0x5B38Da6a701c568545dCfcB03FcB875f56beddC4,
        0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2,
        0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db,
        0x78731D3Ca6b7E34aC0F824c42a7cC18A495cabaB
    ];
    
    // ตรวจสอบว่า Address ที่เรียกใช้งานได้รับอนุญาตหรือไม่
    function isAllowed(address _addr) private view returns (bool) {
        for (uint i = 0; i < allowedAccounts.length; i++) {
            if (allowedAccounts[i] == _addr) {
                return true;
            }
        }
        return false;
    }

    // ฟังก์ชันให้ผู้เล่นเข้าร่วมเกม
    function addPlayer() public payable {
        require(numPlayer < 2, "Game is full"); // ต้องไม่เกิน 2 คน
        if (numPlayer > 0) {
            require(msg.sender != players[0], "Player already joined");
        }
        require(msg.value == 1 ether, "Entry fee is 1 ether"); // ต้องจ่ายค่าเข้า 1 ETH

        reward += msg.value; // เพิ่มเงินรางวัล
        player_not_commit[msg.sender] = true;
        player_not_reveal[msg.sender] = true;
        players.push(msg.sender);
        numPlayer++;

        // เมื่อครบ 2 คนให้เริ่มจับเวลา
        if (numPlayer == 2) {
            timeUnit.setStartTime();
        }
    }

    // ฟังก์ชันขอคืนเงิน (Refund) กรณีมีปัญหา
    function refund() public {
        if (numPlayer == 1) {
            require(address(this).balance >= 1 ether, "Insufficient balance in contract");
            address payable player0 = payable(players[0]);
            player0.transfer(1 ether);
            resetGame();
        } else {
            require(timeUnit.elapsedMinutes() >= 2, "Refund available after 2 minutes");
            if (numReveal < 2) {
                if (player_not_reveal[players[0]]) payable(players[0]).transfer(1 ether);
                if (player_not_reveal[players[1]]) payable(players[1]).transfer(1 ether);
                resetGame();
            } else {
                revert("Refund not available");
            }
        }
    }

    // ฟังก์ชัน Commit ค่า Hash ของตัวเลือก
    function commitinput(bytes32 HashFromConvert) public {
        require(numPlayer == 2, "Game not started yet");
        require(player_not_commit[msg.sender], "Player already played");
        player_not_commit[msg.sender] = false;

        if (msg.sender == players[0]) {
            commitRevealp0.commit(HashFromConvert);
        } else if (msg.sender == players[1]) {
            commitRevealp1.commit(HashFromConvert);
        } else {
            revert("Not a valid player");
        }
        numCommit++;
    }

    // ดึงค่าตัวเลือกจาก Hash
    function getChoice(bytes32 H) private pure returns (uint, bool) {
        uint last_char = uint8(H[31]); // อ่านตัวสุดท้ายของ Hash
        if (last_char >= 48 && last_char <= 52) {
            return (last_char - 48, true);
        } else {
            return (0, false);
        }
    }

    // ฟังก์ชัน Reveal ค่าที่ Commit ไปก่อนหน้า
    function reveal(bytes32 originHash) public {
        require(numPlayer == 2, "Not enough players");
        require(player_not_reveal[msg.sender], "You have already revealed");
        player_originhash[msg.sender] = originHash;
        
        if (msg.sender == players[0]) {
            commitRevealp0.reveal(originHash);
        } else if (msg.sender == players[1]) {
            commitRevealp1.reveal(originHash);
        } else {
            revert("Not a valid player");
        }
        
        player_not_reveal[msg.sender] = false;
        numReveal++;
        if (numReveal == 2) {
            _checkWinnerAndPay();
        }
    }

    // ตรวจสอบผลแพ้ชนะและจ่ายเงินรางวัล
    function _checkWinnerAndPay() private {
        (uint p0Choice, bool p0Valid) = getChoice(player_originhash[players[0]]);
        (uint p1Choice, bool p1Valid) = getChoice(player_originhash[players[1]]);
        address payable account0 = payable(players[0]);
        address payable account1 = payable(players[1]);
        
        //เช็คการใส่ค่าผิด และคืนเงิน
        if (!p0Valid && !p1Valid) {
            account0.transfer(reward / 2);
            account1.transfer(reward / 2);
        } else if (!p0Valid) {
            account1.transfer(reward);
        } else if (!p1Valid) {
            account0.transfer(reward);
        } else {
            // ตรวจสอบผลแพ้ชนะตามกฎ Rock-Paper-Scissors-Lizard-Spock
            if ((p0Choice + 1) % 5 == p1Choice || (p0Choice + 3) % 5 == p1Choice) {
                account1.transfer(reward);
            } else if ((p1Choice + 1) % 5 == p0Choice || (p1Choice + 3) % 5 == p0Choice) {
                account0.transfer(reward);
            } else {
                account0.transfer(reward / 2);
                account1.transfer(reward / 2);
            }
        }
        resetGame();
    }

    // รีเซ็ตเกม
    function resetGame() private {
        delete players;
        numPlayer = 0;
        reward = 0;
        numCommit = 0;
        numReveal = 0;
    }
}
