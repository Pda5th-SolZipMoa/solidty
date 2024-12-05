// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title RealEstateToken
/// @notice 부동산 토큰화 및 청약 기능 제공
contract RealEstateToken is ERC1155, Ownable {
    struct Property {
        string tokenId;          // 고유 토큰 ID
        address owner;           // 집주인 주소
        uint256 totalSupply;     // 발행된 총 토큰 수량
        uint256 remainingTokens; // 잔여 토큰 수량
        string buildingCode;     // 건물 코드
        uint256 floorNumber;     // 층수
    }

    struct Subscription {
        address investor;        // 투자자 주소
        uint256 amount;          // 청약 수량
        uint256 depositedFunds;  // 예치된 자금 (ETH)
    }

    mapping(string => Property) public properties; // 토큰 ID별 부동산 정보
    mapping(string => Subscription[]) public subscriptions; // 토큰 ID별 청약 정보
    mapping(string => bool) public isSubscriptionActive; // 청약 활성화 상태
    string[] public allTokenIds; // 발행된 모든 토큰 ID를 저장

    event TokenMinted(
        address indexed owner,
        string tokenId,
        uint256 totalSupply,
        string buildingCode,
        uint256 floorNumber
    );
    event SubscriptionOpened(string tokenId);
    event Subscribed(address indexed investor, string tokenId, uint256 amount, uint256 depositedFunds);
    event SubscriptionClosed(string tokenId);
    event TokensAllocated(string tokenId);

    constructor() ERC1155("https://example.com/metadata/{id}.json") Ownable(msg.sender) {}

    /// @notice 새로운 토큰 발행
    /// @param totalSupply 발행할 총 토큰 수량
    /// @param buildingCode 건물 코드
    /// @param floorNumber 층수
    /// @return tokenId 발행된 토큰 ID
   function mintToken(
    uint256 totalSupply,
    string memory buildingCode,
    uint256 floorNumber
) external onlyOwner returns (string memory) {
    require(totalSupply > 0, "Total supply must be greater than zero");
    require(bytes(buildingCode).length > 0, "Building code must not be empty");
    require(floorNumber > 0, "Floor number must be greater than zero");

    string memory tokenId = string(abi.encodePacked(buildingCode, "_", uint2str(floorNumber)));
    require(properties[tokenId].totalSupply == 0, "Token ID already exists");

    // 토큰 정보 저장
    properties[tokenId] = Property({
        tokenId: tokenId,
        owner: msg.sender,
        totalSupply: totalSupply,
        remainingTokens: totalSupply,
        buildingCode: buildingCode,
        floorNumber: floorNumber
    });

    allTokenIds.push(tokenId); // 발행된 토큰 ID를 저장

    // 토큰 발행
    _mint(msg.sender, uint256(keccak256(bytes(tokenId))), totalSupply, "");
    emit TokenMinted(msg.sender, tokenId, totalSupply, buildingCode, floorNumber);

    // 청약 활성화
    _activateSubscription(tokenId);

    return tokenId;
}

/// @dev 청약 활성화를 내부에서 호출하기 위한 함수
function _activateSubscription(string memory tokenId) internal {
    require(properties[tokenId].totalSupply > 0, "Token does not exist");
    require(!isSubscriptionActive[tokenId], "Subscription already active");

    isSubscriptionActive[tokenId] = true;
    emit SubscriptionOpened(tokenId);
}

    /// @notice 모든 발행된 토큰 ID 반환
    /// @return 전체 토큰 ID 배열
    function getAllTokenIds() external view returns (string[] memory) {
        return allTokenIds;
    }

    /// @notice 청약 등록
/// @param tokenId 청약할 토큰 ID
/// @param amount 신청할 토큰 수량
/// @param pricePerToken 각 토큰의 가격 (ETH 단위)
function subscribe(string memory tokenId, uint256 amount, uint256 pricePerToken) external payable {
    require(amount > 0, "Amount must be greater than zero"); // 최소 수량 확인
    require(properties[tokenId].remainingTokens >= amount, "Not enough tokens available"); // 잔여 토큰 확인
    require(pricePerToken > 0, "Price per token must be greater than zero"); // 유효한 가격 확인
    require(isSubscriptionActive[tokenId], "Subscription is not active"); // 청약 활성화 상태 확인

    uint256 totalPrice = pricePerToken * amount; // 총 금액 계산

    // 사용자가 지불한 금액 확인
    require(msg.value >= totalPrice, "Insufficient funds sent"); // 부족한 금액 확인

    // 청약 데이터 저장
    subscriptions[tokenId].push(Subscription({
        investor: msg.sender,
        amount: amount,
        depositedFunds: totalPrice
    }));

    properties[tokenId].remainingTokens -= amount; // 잔여 토큰 감소

    // 잉여 금액 반환 (사용자가 보낸 금액이 초과하는 경우)
    if (msg.value > totalPrice) {
        payable(msg.sender).transfer(msg.value - totalPrice); // 초과 금액 반환
    }

    emit Subscribed(msg.sender, tokenId, amount, totalPrice);
}


    /// @notice 특정 토큰 ID가 존재하는지 확인하고, 상세 정보를 반환
    /// @param tokenId 확인할 토큰 ID
    /// @return exists 해당 토큰 ID의 존재 여부 (true/false)
    /// @return property 토큰의 상세 정보 (존재할 경우)
    function getTokenDetails(string memory tokenId) 
        public 
        view 
        returns (bool exists, Property memory property) 
    {
        exists = properties[tokenId].totalSupply > 0;
        if (exists) {
            property = properties[tokenId];
        }
    }

    /// @notice 청약 종료 및 비례 배분
    /// @param tokenId 청약할 토큰 ID
    function closeSubscription(string memory tokenId) external onlyOwner {
        require(isSubscriptionActive[tokenId], "Subscription is not active");

        Subscription[] storage tokenSubscriptions = subscriptions[tokenId];
        uint256 totalRequested = 0;
        uint256 totalSupply = properties[tokenId].totalSupply;

        for (uint256 i = 0; i < tokenSubscriptions.length; i++) {
            totalRequested += tokenSubscriptions[i].amount;
        }

        for (uint256 i = 0; i < tokenSubscriptions.length; i++) {
            Subscription storage sub = tokenSubscriptions[i];
            uint256 allocated = (totalRequested > totalSupply)
                ? (sub.amount * totalSupply) / totalRequested
                : sub.amount;

            if (allocated > 0) {
                _safeTransferFrom(properties[tokenId].owner, sub.investor, uint256(keccak256(bytes(tokenId))), allocated, "");
                sub.depositedFunds = 0;
            }
        }

        isSubscriptionActive[tokenId] = false;
        emit SubscriptionClosed(tokenId);
        emit TokensAllocated(tokenId);
    }

    /// @notice 정수를 문자열로 변환
    /// @param value 변환할 정수 값
    /// @return 변환된 문자열
    function uint2str(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
