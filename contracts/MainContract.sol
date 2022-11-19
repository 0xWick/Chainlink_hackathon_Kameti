// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

// * Get Chainlink VRF Contract

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

contract KametiContract is VRFConsumerBaseV2 {

    // * Random Number Code
    // * Random Number Events
    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(uint256 requestId, uint256[] randomWords);

    VRFCoordinatorV2Interface COORDINATOR;

    // Your subscription ID.
    uint64 s_subscriptionId;

    // past requests Id.
    uint256[] public requestIds;
    uint256 public lastRequestId;

    // The gas lane to use, which specifies the maximum gas price to bump to.
    // For a list of available gas lanes on each network,
    // see https://docs.chain.link/docs/vrf/v2/subscription/supported-networks/#configurations
    bytes32 keyHash =
        0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f;

    uint32 callbackGasLimit = 1000000;

    // The default is 2, but you can set this higher.
    uint16 requestConfirmations = 3;

    // For this example, retrieve 2 random values in one request.
    // Cannot exceed VRFCoordinatorV2.MAX_NUM_WORDS.
    uint32 numWords = 1;

    /**
     * HARDCODED FOR MUMBAI TESTNET
     * COORDINATOR: 0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed
     */
    constructor(uint64 subscriptionId)
        VRFConsumerBaseV2(0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed)
    {
        COORDINATOR = VRFCoordinatorV2Interface(
            0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed
        );
        s_subscriptionId = subscriptionId;
    }

    // Assumes the subscription is funded sufficiently.
    // Call VRF Contract and request random Numbers
    function requestRandomWords() internal returns (uint256 requestId) {
        // Will revert if subscription is not set and funded.
        requestId = COORDINATOR.requestRandomWords(
            keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );

        emit RequestSent(requestId, numWords);
        return requestId;
    }

    // * ----------- Main Contract Code ----------

    // ** Kameti (ROSCAs): A rotating savings and credit association is a group of individuals who
    // ** agree to meet for a defined period in order to save and borrow together, a form of
    // ** combined peer-to-peer banking and peer-to-peer lending.

    // * New Kameti Created
    event kametiCreated(
        bytes32 kametiId,
        string kametiDataCID,
        address organizer,
        uint256 monthlyPayment,
        uint256 months,
        address payable[] kametiMembers,
        uint256 timestamp
    );

    // * New Kameti Payment
    event newKametiPayment(bytes32 kametiId, address payer, uint256 payment);

    // * Monthly Check of Kameti & Choosing Winner for the Saving Pool
    event monthlyCheckPerformed(
        bytes32 kametiId,
        uint256 month,
        address winner
    );

    // * Kameti Ended (with Conflict or Success)
    event kametiEnded(
        bytes32 kametiId,
        uint256 remainingPool, // * sent to the organizer
        bool kametiEndedSuccess,
        bool kametiEndedConflict
    );

    // * Kameti Winner Decided
    event kametiWinner(address payable winer);

    // ** Data Structure
    // ? Kameti Member
    struct kametiMember {
        bytes32 kametiId;
        address payable memberAddress;
        uint256 monthsPaid;
        bool kametiReceived;
    }
    // ? Main data of a Kameti to be used for futher calculations
    struct Kameti {
        bytes32 kametiId; // * Unique id of every kameti
        string kametiDataCID; // * Data Related to Kameti
        uint256 lastCheckTime; // * For tracking Monthly Checks
        address payable kametiOrganizer; // * Gets a little cut for doing due dilligence on group
        address payable[] memberAddresses;
        uint256 monthlyPayment;
        uint256 months;
        uint256 currentMonth;
        uint256 poolSize;
        uint256 totalMembers;
        uint256 requestId; // * Request Id for Random Numbers
        bool kametiEndedSuccess;
        bool kametiEndedConflict;
    }

    // * keep track of multiple kameti's with their id
    mapping(bytes32 => Kameti) public idToKameti;

    mapping(uint256 => Kameti) public requestToKameti;
    mapping(bytes32 => address payable) public kametiToWinner;
    bool winnerDecided;
    mapping(bytes32 => mapping(address => kametiMember))
        public kametiToaddressToMember;

    // ** Create Kameti
    // ? Anyone can create a new kameti with the right parameters like a game lobby
    // ? Organizer has no control over the kameti

    // * Start Kameti
    // @params
    // array of addresses of members
    // Related data Content Id from IPFS
    // _monthlyPayment for Kameti 
        //  1 _monthlyPayment => 0.0001 ether
        // 10 _monthlyPayment => 0.001 ether
    function createKameti(
        address payable[] memory _kametiMembers,
        string memory _kametiDataCID,
        uint256 _monthlyPayment
    ) public {
        //* Calculate unique Kameti Id
        bytes32 kametiId = keccak256(
            abi.encodePacked(
                msg.sender,
                address(this),
                _monthlyPayment,
                block.number
            )
        );

        // * Create Members with details and save into mapping
        for (uint i = 0; i < _kametiMembers.length; i++) {
            // * Get member's address
            address memberAddress = _kametiMembers[i];

            // * Create a temporary kametiMember(struct)
            kametiMember memory tempKametiMember = kametiMember(
                kametiId,
                payable(memberAddress),
                0,
                false
            );

            // * Push to addressToMember Mapping
            kametiToaddressToMember[kametiId][memberAddress] = tempKametiMember;
        }

        uint256 totalMembers = _kametiMembers.length;

        // // -----------------------
        // ! Do the Random kura andazi, and define everyone's Kameti Month at the start

        uint256 requestId = requestRandomWords();

        // * Downsize the amount in decimals
        // 1 _monthlyPayment => 0.0001 ether
        // 10 _monthlyPayment => 0.001 ether
        uint256 payment = _monthlyPayment * 10**14;

        //* Create Kameti
        idToKameti[kametiId] = Kameti(
            kametiId,
            _kametiDataCID,
            block.timestamp,
            payable(msg.sender),
            _kametiMembers,
            0.001 ether,
            totalMembers,
            1,
            payment * totalMembers,
            totalMembers,
            requestId,
            false,
            false
        );

        // * Add to request Id
        requestToKameti[requestId] = idToKameti[kametiId];

        // * Emit New Kameti Created
        emit kametiCreated(
            kametiId,
            _kametiDataCID,
            msg.sender,
            payment,
            totalMembers,
            _kametiMembers,
            block.timestamp
        );
    }

    // ** Generate Random Number
    // ? Chainlink VRF for selecting the next person to access the pool
    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        // * Get Kameti
        Kameti storage kameti = requestToKameti[_requestId];

        uint256 winnerIndex = _randomWords[0] % kameti.totalMembers;

        kametiToWinner[kameti.kametiId] = kameti.memberAddresses[winnerIndex];

        emit kametiWinner(kameti.memberAddresses[winnerIndex]);
        emit RequestFulfilled(_requestId, _randomWords);
    }

    // * Make Kameti Payment
    // ? Make a payment to the kameti you are a part of
    function payKameti(bytes32 kametiId) public payable {
        // * Get Kameti
        Kameti storage kameti = idToKameti[kametiId];

        // * Check kameti Prize
        require(msg.value >= kameti.monthlyPayment, "Wrong Payment");

        // * Check Kameti Status
        require(kameti.kametiEndedSuccess == false, "Kameti Ended Success");
        require(kameti.kametiEndedConflict == false, "Kameti Ended Conflict");

        // * Check if Sender is a kameti Member
        // * Check if Current Month Payment Done

        // * Get Current Kameti Member Data from mapping
        kametiMember memory currentKametiMember = kametiToaddressToMember[
            kametiId
        ][msg.sender];

        // * Check if current Member already paid kameti
        // * Check if he is a member of current kameti

        if (
            kameti.kametiId == currentKametiMember.kametiId &&
            currentKametiMember.memberAddress == msg.sender
        ) {
            require(
                kameti.currentMonth > currentKametiMember.monthsPaid,
                "Already Paid"
            );
            // ! Take Organizer's cut
            currentKametiMember.monthsPaid++;

            // * Update mapping
            kametiToaddressToMember[kametiId][msg.sender] = currentKametiMember;

            // * Emit New Kameti Payment
            emit newKametiPayment(kametiId, msg.sender, msg.value);
        } else {
            revert("Not a Kameti Member");
        }
    }

    // * Check Kameti & Pay the Winner(if no conflict)
    // ? Call with Chainlink Keepers every 10th of a month
    function checkKameti(bytes32 kametiId) public payable {
        // * Get Kameti
        Kameti storage kameti = idToKameti[kametiId];

        // * Time when last Checked
        uint256 lastCheck = kameti.lastCheckTime;

        // * Check if 2 minutes have passed since last check
        require(block.timestamp >= lastCheck + 2 minutes, "Too Early");

        // * Get Current Month for easy Check
        uint256 currentMonth = kameti.currentMonth;
        uint256 lastMonth = kameti.totalMembers;

        // * Last Check Time

        // * Check Kameti Status
        require(kameti.kametiEndedSuccess == false, "Kameti Ended Success");
        require(kameti.kametiEndedConflict == false, "Kameti Ended Conflict");

        // * End the kameti with success
        // ? Everyone received their kameti,
        bool isLastMonth = false;
        if (currentMonth == lastMonth) {
            isLastMonth = true;
        }

        // * Get the Current Winner's address
        address payable currentWinner;
        if (currentMonth == 1) {
            currentWinner = kametiToWinner[kametiId];
        } else {
            currentWinner = kameti.memberAddresses[currentMonth]; // * for getting the array index of the winner
        }
        bool noConflict = false;
        // * Check if Everyone have paid their Kameti
        // ? Check Conflict
        for (uint8 i = 0; i < kameti.totalMembers; i++) {
            // * Get address of current Member
            address currentMemberAddress = kameti.memberAddresses[i];
            // * Get current Kameti Member
            kametiMember memory currentKametiMember = kametiToaddressToMember[
                kametiId
            ][currentMemberAddress];

            // * Check if someone haven't paid
            // ? Raise Conflict if someone is default
            if (currentKametiMember.monthsPaid != currentMonth) {
                // * Kameti Ended with Conflict
                conflictKameti(kametiId);
                noConflict = false;
                break;
            } else {
                noConflict = true;
            }
        }
        // * If no Conflict, Find & Pay the winner
        if (noConflict) {
            for (uint8 i = 0; i < kameti.totalMembers; i++) {
                // * Get address of current Member
                address currentMemberAddress = kameti.memberAddresses[i];
                // * Get current Kameti Member
                kametiMember
                    memory currentKametiMember = kametiToaddressToMember[
                        kametiId
                    ][currentMemberAddress];

                // * Haven't already received the kameti
                // * is the winner
                if (
                    currentKametiMember.kametiReceived != true &&
                    currentWinner == currentKametiMember.memberAddress
                ) {
                    // * Update winner's account details
                    // ? kameti Received
                    currentKametiMember.kametiReceived = true;

                    // * Send Kameti to the winner
                    currentWinner.transfer(address(this).balance);

                    // * Update the Mapping
                    kametiToaddressToMember[kametiId][
                        currentMemberAddress
                    ] = currentKametiMember;

                    // * Update LastCheckTime
                    kameti.lastCheckTime = block.timestamp;

                    // * Update Current Month
                    kameti.currentMonth++;

                    // * Emit monthly Kameti Paid
                    emit monthlyCheckPerformed(
                        kametiId,
                        currentMonth,
                        currentWinner
                    );

                    break;
                }
            }
        }

        // * Check if last month, mark Kameti Ended Success
        // ? Send the remaining(if any) balance to the organizer
        if (isLastMonth && noConflict) {
            kameti.kametiEndedSuccess = true;

            uint256 contractBalance = address(this).balance;

            // * Transfer any remaining funds to the organizer
            kameti.kametiOrganizer.transfer(contractBalance);

            // * Emit Kameti Ended Success
            emit kametiEnded(kametiId, contractBalance, true, false);
        }
    }

    // * Conflict Kameti
    // ? If someone go default in a kameti
// Note: Ending the contract doesn't matter for the kameti as long as we have all the transaction details on an immutable ledger we can accuse all the culprits.
// Also thanks to PolygonId good people's Id is private, and culprits Ids can be shared with the law.
    function conflictKameti(bytes32 kametiId) internal {
        // * Get Kameti
        Kameti storage kameti = idToKameti[kametiId];

        // * End the Kameti With Conflict
        kameti.kametiEndedConflict = true;

        uint256 contractBalance = address(this).balance;

        // * Transfer any remaining funds to the organizer
        kameti.kametiOrganizer.transfer(contractBalance);

        // * Emit kameti Ended
        emit kametiEnded(kametiId, contractBalance, false, true);
    }
}
