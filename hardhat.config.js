/**
 * @type import('hardhat/config').HardhatUserConfig
 */
require("@nomiclabs/hardhat-waffle");
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.6.0"
      },
      {
        version: "0.6.6"
      },
      {
        version: "0.8.0"
      }
    ]
  }

};
