// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;


interface IReferral {
    function recordReferral(address user, address referrer) external;
    function recordReferralCommission(address referrer, uint256 commission) external;
    function getReferrer(address user) external view returns (address);
}

interface ERC721 /* is ERC165 */ {
    function balanceOf(address _owner) external view returns (uint256);
    function ownerOf(uint256 _tokenId) external view returns (address);
    function transferFrom(address _from, address _to, uint256 _tokenId) external payable;
    function totalSupply() external view returns (uint256);
}

interface IDogeFoodToken {
    function mint(address _user, uint256 _amount) external;
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function assignMinterRole(address account) external;
}

interface IBoosterNFT {
    function getNftType(uint256 tokenId) external view returns (uint8 index);
}
