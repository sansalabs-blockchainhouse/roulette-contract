require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-etherscan");

module.exports = {
  solidity: "0.8.18",
  networks: {
    polygon_mainnet: {
      url: `https://morning-weathered-fog.matic.discover.quiknode.pro/a28deafbeced08422cba57ed873fc6fddcf65a59/`,
      accounts: ['5507df5ba9ee327653c37e0f45b5f499d41cffa5ce46c0ce7563488fa34988c7'],
    },
  },
  etherscan: {
    apiKey: 'R24JN1FSMVB46VXGTB7R8ST7926GB8P2NM',
  },
};
