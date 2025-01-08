//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC404Legacy.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

// Pandora合约继承自ERC404Legacy
contract Pandora is ERC404Legacy {
  // NFT元数据URI
  string public dataURI;
  // NFT基础URI
  string public baseTokenURI;

  // 构造函数
  constructor(
    address _owner
  ) ERC404Legacy("Pandora", "PANDORA", 18, 10000, _owner) {
    // 将所有者加入白名单
    whitelist[_owner] = true;
    // 初始化所有者代币余额
    balanceOf[_owner] = 10000 * 10 ** 18;
  }

  // 设置NFT元数据URI,只有所有者可调用
  function setDataURI(string memory _dataURI) public onlyOwner {
    dataURI = _dataURI;
  }

  // 设置NFT基础URI,只有所有者可调用
  function setTokenURI(string memory _tokenURI) public onlyOwner {
    baseTokenURI = _tokenURI;
  }

  // 设置代币名称和符号,只有所有者可调用
  function setNameSymbol(
    string memory _name,
    string memory _symbol
  ) public onlyOwner {
    _setNameSymbol(_name, _symbol);
  }

  // 获取NFT的元数据URI
  function tokenURI(uint256 id) public view override returns (string memory) {
    // 如果设置了基础URI,直接返回基础URI+tokenId
    if (bytes(baseTokenURI).length > 0) {
      return string.concat(baseTokenURI, Strings.toString(id));
    } else {
      // 否则根据tokenId生成随机种子
      uint8 seed = uint8(bytes1(keccak256(abi.encodePacked(id))));
      string memory image;
      string memory color;

      // 根据随机种子分配不同的图片和颜色属性
      if (seed <= 100) {
        image = "1.gif";
        color = "Green";
      } else if (seed <= 160) {
        image = "2.gif";
        color = "Blue";
      } else if (seed <= 210) {
        image = "3.gif";
        color = "Purple";
      } else if (seed <= 240) {
        image = "4.gif";
        color = "Orange";
      } else if (seed <= 255) {
        image = "5.gif";
        color = "Red";
      }

      // 构建JSON元数据前半部分
      string memory jsonPreImage = string.concat(
        string.concat(
          string.concat('{"name": "Pandora #', Strings.toString(id)),
          '","description":"A collection of 10,000 Replicants enabled by ERC404, an experimental token standard.","external_url":"https://pandora.build","image":"'
        ),
        string.concat(dataURI, image)
      );
      // 构建JSON元数据中间部分
      string memory jsonPostImage = string.concat(
        '","attributes":[{"trait_type":"Color","value":"',
        color
      );
      // JSON元数据结尾部分
      string memory jsonPostTraits = '"}]}';

      // 返回完整的JSON元数据
      return
        string.concat(
          "data:application/json;utf8,",
          string.concat(
            string.concat(jsonPreImage, jsonPostImage),
            jsonPostTraits
          )
        );
    }
  }
}
