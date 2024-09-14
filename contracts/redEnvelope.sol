// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";


contract RedEnvelope is VRFConsumerBaseV2Plus {
    enum Type {
        ERC20,
        ETH
    }

    event createRedEnvelope(
        bytes32 hash,
        Type t,
        uint balance,
        bool allowAll,
        address[] allowList,
        uint maxReceiver,
        bool avg,
        uint avgMonty,
        uint timeOutBlocks
    );

    struct Envelope {
        Type t;
        ERC20 token;
        address sender;
        uint balance;
        bool allowAll;
        uint32 maxReceiver;
        bool avg; // 平均主义，每个红包的价值等于balance/maxReceiver //填false则使用随机红包
        uint avgMonty;
        uint timeOutBlocks; //超时可以回收红包
        address[] received;
    }
    mapping(bytes32 => Envelope) public envelopes;
    mapping(bytes32 => mapping(address => bool)) public addressAllowList;
    mapping(bytes32 => mapping(address => bool)) addressGotList;
    mapping(uint => bytes32) openWithVRF;
    mapping(ERC20 => uint) ERC20Balance;
    mapping(bytes32 => uint[]) VRFKey;

    // VRFV2PlusClient public COORDINATOR;
    bytes32 keyHash = 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae;

    uint256 s_subscriptionId;

    uint32 immutable callbackGasLimit = 100000;

    // The default is 3, but you can set this higher.
    uint16 immutable requestConfirmations = 3;

    constructor(
        uint256 _subscriptionId,
        address _coordinator
    ) VRFConsumerBaseV2Plus(_coordinator){
        s_subscriptionId = _subscriptionId;
    }

    function createETHredEnvelope(
        bool allowAll,
        address[] memory allowList,
        uint32 maxReceiver,
        bool avg,
        uint timeOutBlocks
    ) public payable returns (bytes32) {
        require(
            timeOutBlocks > 10 && msg.value > 0 && msg.value >= maxReceiver,
            "invalid input"
        );
        require(maxReceiver > 0, "invalid maxReceiver");
        uint avgMonty = 0;
        if (avg) {
            avgMonty = msg.value / maxReceiver;
        }
        address[] memory received;
        Envelope memory envelope = Envelope({
            t: Type.ETH,
            token: ERC20(address(0)),
            sender: msg.sender,
            balance: msg.value,
            allowAll: allowAll,
            maxReceiver: maxReceiver,
            avg: avg,
            avgMonty: avgMonty,
            timeOutBlocks: timeOutBlocks + block.number,
            received:received
        });
        bytes32 hash = keccak256(abi.encodePacked(msg.sender, block.timestamp));
        for (uint i = 0; i < allowList.length; i++) {
            addressAllowList[hash][allowList[i]] = true;
        }
        require(envelopes[hash].balance == 0, "envelop balance is not 0");
        envelopes[hash] = envelope;
        emit createRedEnvelope(
            hash,
            Type.ETH,
            msg.value,
            allowAll,
            allowList,
            maxReceiver,
            avg,
            avgMonty,
            timeOutBlocks
        );
        return hash;
    }

    function createERC20redEnvelope(
        address token,
        uint size,
        bool allowAll,
        address[] memory allowList,
        uint32 maxReceiver,
        bool avg,
        uint timeOutBlocks
    ) public returns (bytes32) {
        require(
            timeOutBlocks > 10 && maxReceiver > 0 && token != address(0),
            "invalid input"
        );
        require(maxReceiver > 0, "invalid maxReceiver");
        uint avgMonty = 0;
        if (avg) {
            avgMonty = size / maxReceiver;
        }
        uint approved = ERC20(token).allowance(msg.sender,address(this));
        require(approved>=ERC20Balance[ERC20(token)]+size);
        ERC20Balance[ERC20(token)] += size;
        address[] memory received;
        Envelope memory envelope = Envelope({
            t: Type.ERC20,
            token: ERC20(token),
            sender: msg.sender,
            balance: size,
            allowAll: allowAll,
            maxReceiver: maxReceiver,
            avg: avg,
            avgMonty: avgMonty,
            timeOutBlocks: timeOutBlocks + block.number,
            received:received
        });
        bytes32 hash = keccak256(abi.encodePacked(msg.sender, block.timestamp));
        for (uint i = 0; i < allowList.length; i++) {
            addressAllowList[hash][allowList[i]] = true;
        }
        require(envelopes[hash].balance == 0, "envelop balance is not 0");
        envelopes[hash] = envelope;
        emit createRedEnvelope(
            hash,
            Type.ERC20,
            size,
            allowAll,
            allowList,
            maxReceiver,
            avg,
            avgMonty,
            timeOutBlocks
        );
        return hash;
    }

    function allowSome(bytes32 hash, address[] memory allowList) public {
        require(envelopes[hash].balance != 0, "envelop balance is 0");
        require(envelopes[hash].sender == msg.sender,"only envelops sender can do this");
        for (uint i = 0; i < allowList.length; i++) {
            addressAllowList[hash][allowList[i]] = true;
        }
    }

    function getBalance(bytes32 hash) public view returns (uint) {
        return envelopes[hash].balance;
    }

    function get(bytes32 hash) public {
        require(envelopes[hash].balance != 0, "envelop balance is 0");
        require(!addressGotList[hash][msg.sender], "has got");
        require(
            envelopes[hash].timeOutBlocks > block.number,
            "envelop timeOutBlocks is not enough"
        );
        require(
            addressAllowList[hash][msg.sender] || envelopes[hash].allowAll,
            "not allow"
        );
        require(envelopes[hash].received.length < envelopes[hash].maxReceiver, "no more");
        envelopes[hash].received.push(msg.sender);
        addressGotList[hash][msg.sender] = true;
        if (envelopes[hash].avg) {
            // 先记账，再转账
            require(
                envelopes[hash].avgMonty <= envelopes[hash].balance,
                "avgMonty is 0"
            );
            envelopes[hash].balance -= envelopes[hash].avgMonty;
            if (envelopes[hash].t == Type.ETH) {
                payable(msg.sender).transfer(envelopes[hash].avgMonty);
            } else if (envelopes[hash].t == Type.ERC20) {
                ERC20Balance[envelopes[hash].token] -= envelopes[hash].avgMonty;
                require(envelopes[hash].token.transferFrom(
                    envelopes[hash].sender,
                    msg.sender,
                    envelopes[hash].avgMonty
                ),"transferFrom failed");
            }
        }
        if(envelopes[hash].received.length==envelopes[hash].maxReceiver){
            openEnvelopes(hash);
        }
    }

    function openEnvelopes(bytes32 hash)public{
        require(
            envelopes[hash].timeOutBlocks < block.number || envelopes[hash].received.length == envelopes[hash].maxReceiver,
            "envelop timeOutBlocks is not enough"
        );
        require(envelopes[hash].maxReceiver > 0,"max receriver max more than 0");
        if (envelopes[hash].avg){
            if (envelopes[hash].t == Type.ETH){
                uint t = envelopes[hash].balance;
                envelopes[hash].balance =0;
                payable(envelopes[hash].sender).transfer(t);
            }else if (envelopes[hash].t == Type.ERC20){
                uint t = envelopes[hash].balance;
                envelopes[hash].balance = 0;
                ERC20Balance[envelopes[hash].token] -= envelopes[hash].balance;
                require(envelopes[hash].token.transferFrom(envelopes[hash].sender,envelopes[hash].sender,t),"transferFrom failed");

            }
            delete envelopes[hash];
        }else{
            uint requestId = s_vrfCoordinator.requestRandomWords(
                VRFV2PlusClient.RandomWordsRequest({
                    keyHash:keyHash,
                    subId:s_subscriptionId,
                    requestConfirmations:requestConfirmations,
                    callbackGasLimit:callbackGasLimit,
                    numWords:uint32(envelopes[hash].received.length),
                    extraArgs: VRFV2PlusClient._argsToBytes(
                        VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                    )
                })
            );
            openWithVRF[requestId] = hash;
        }
    }
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] calldata randomWords
    ) internal override {
        require(randomWords.length == envelopes[openWithVRF[requestId]].received.length);
        VRFKey[openWithVRF[requestId]] = randomWords;
    }

    function openVRFEnvelop(bytes32 hash)public {
        uint[] memory randomWords = VRFKey[hash];
        require(envelopes[hash].maxReceiver > 0,"max receriver max more than 0");
        require(randomWords.length!=0,"can not get vrf words");
        uint16[] memory words = new uint16[](randomWords.length);
        // 计算每一个小分段的权重
        uint sum;
        for(uint i=0;i<randomWords.length;i++){
            words[i] = uint16(randomWords[i]);
            if (words[i] == 0){words[i]=10;}
            sum+=words[i];
        }

        uint b = envelopes[hash].balance;
        // 如果是eth
        if (envelopes[hash].t == Type.ETH){
            for(uint i=0;i<randomWords.length;i++){
                // 根据权重分红包
                envelopes[hash].balance -= b*words[i]/sum;
                payable(envelopes[hash].received[i]).transfer(b*words[i]/sum);
            }
            // 多余的退回去
            uint t = envelopes[hash].balance;
            envelopes[hash].balance =0;
            payable(envelopes[hash].sender).transfer(t);
        }else if (envelopes[hash].t == Type.ERC20){
            for(uint i=0;i<randomWords.length;i++){
                envelopes[hash].balance -= b*words[i]/sum;
                ERC20Balance[envelopes[hash].token] -= b*words[i]/sum;
                require(envelopes[hash].token.transferFrom(
                    envelopes[hash].sender,
                    envelopes[hash].received[i],
                    b*words[i]/sum),
                    "transferFrom failed");
            }
            if (envelopes[hash].balance != 0){
                uint t =  envelopes[hash].balance;
                envelopes[hash].balance = 0;
                ERC20Balance[envelopes[hash].token] -= t;
                require(envelopes[hash].token.transferFrom(
                    envelopes[hash].sender,
                    envelopes[hash].sender,
                    t),
                    "transfer to sender failed");
            }
        }
        delete envelopes[hash];
    }
}
