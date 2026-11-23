#!/bin/sh
# chiikawa-wallpaper.com 의 투명 배경 스티커/GIF를 받아 스프라이트 폴더에 넣는다.
# 이미지는 저장소에 넣지 않는다(원작 그림). 개인 PC에서만 쓴다.
set -eu
dest="${1:-$HOME/Library/Application Support/ChiikawaDesktop}"
r2=https://r2.chiikawa-wallpaper.com/wallpaper
fetch() { # <캐릭터> <상태-이름> <경로>
  mkdir -p "$dest/$1"
  ext="${3##*.}"
  curl -fsSL -A "Mozilla/5.0" -o "$dest/$1/$2.$ext" "$r2/$3"
}
fetch chiikawa idle-a 20260930/01074e34195ec23357f8acc2bc55cde5.png
fetch chiikawa idle-b 20260930/01d3445655a48d7b274deeecb7b86cab.png
fetch chiikawa idle-c 20260930/78238605ad97cddcd552d8db85b9dd26.png
fetch chiikawa idle-d 20260930/65669cdec356b95f79f1aa6451d2001c.png
fetch chiikawa walk-a 20260930/1ab22e2b3265f3369fd3831d842e871c.png
fetch chiikawa held-a gif/356cc8c93500999bfc3110eeb4e0a800.gif
fetch chiikawa fall-a 20260930/8eca919f0675cea9f5ac4e61a5a0d75e.png
fetch chiikawa react-c 20260930/1d86f29ac3125a33d53e98d7c67fecb5.png
fetch chiikawa cry-a 20260930/1b01638a6e78f531081e446a4c68af55.png
fetch chiikawa eat-a 20260930/4fdd5866557027d4c5ff27c1e9541767.png
fetch chiikawa eat-b 20260930/05e8a68c57437fa29fc7b1622ae28abf.png
fetch chiikawa sleep-a 20260930/44a16abb753b7be7f5588cb4a21e3e97.png
fetch chiikawa sleep-b 20260930/5c7fd038b7e620933d4c9ffba1f8470d.png
fetch chiikawa dance-b 20260930/74e4b1019e6dee768dc90f0d0eac550c.png
fetch chiikawa weed-a 20260930/b6516fe584dc53804c2d4133629be664.png
fetch hachiware idle-a 20260930/ef95abaea5fce469a7acf5fa9ed977fe.png
fetch hachiware idle-b 20260930/52f5915f60ba63dac052c45c2e8584ac.png
fetch hachiware idle-c 20260930/90d86eb4992987c9255c3bc42293449d.png
fetch hachiware idle-d 20260930/a66812ec2ec94f814b32fbdfad4a3e1d.png
fetch hachiware walk-a 20260930/9a4d03c739c7e930c5453a426e1626ca.png
fetch hachiware held-a 20260930/a48fc0cc5b5003b2da1f4f7b6d46d93b.png
fetch hachiware fall-a 20260930/7037936e0bbe4334dc4c460bdf07bc50.png
fetch hachiware react-b 20260930/23b322b4985113c278e901be9fac24f3.png
fetch hachiware react-c 20260930/be182664dfd2c3107d843d6eb3bb4f76.png
fetch hachiware cry-a 20260930/cb3ea3e30ecef2a1bfe1b6e9b40ca5ec.png
fetch hachiware eat-a 20260930/a344fe93599f3d0e6369a78fb9e2bc04.png
fetch hachiware eat-b 20260930/803da167b709cfb3a62f80d0920d9a91.png
fetch hachiware eat-c 20260930/1b525d0936efe987adadbcd300983144.png
fetch hachiware sleep-a 20260930/f0cd8f60f6f521a32d3aa477c7b6df10.png
fetch hachiware dance-a 20260930/e30f0bd0f2adabccc1b62f0568e6421b.png
fetch hachiware dance-b 20260930/a199d143eab04bef5f07abc8b81337b5.png
fetch usagi idle-a 20260930/ce90ab48763ad70f03f76c20a8e54353.png
fetch usagi idle-b 20260930/2947994c9142922f325ceae78a35b96a.png
fetch usagi idle-c 20260930/ebf432c57014f46925eebbd4074a06a3.png
fetch usagi idle-d 20260930/381e036945b1ccae87f8f357caae08d4.png
fetch usagi walk-a 20260930/c87d178e468e87dca8c6b7643996c53d.png
fetch usagi walk-b 20260930/d81d094ddaf2217c983a9dcc8eda9b3c.png
fetch usagi held-a 20260930/136d04eac42dcb37adc46979fa7bc65e.png
fetch usagi fall-a 20260930/9d4d7cb4a11631bc0b3794137e7f90a7.png
fetch usagi fall-b 20260930/45137ee1e53665a1b57ed20ae5885323.png
fetch usagi react-a 20260930/5cc009e2f398dbec0b4fec132bfc748d.png
fetch usagi react-c 20260930/142f6478ca8cc07aea183f7fe01563e8.png
fetch usagi cry-a 20260930/624e99421aae0629bc208b51e9bd9b2e.png
fetch usagi eat-a 20260930/2ed9476d5c71082f5c46f7163e6eba6c.png
fetch usagi sleep-a 20260930/13b2143e2806b7eceab828b75a9d64c9.png
fetch usagi sleep-b 20260930/9e409a86ec98f814f4e6fcc2a348ecc6.png
fetch usagi dance-a 20260930/74a2d14f72fc64068ba0027eb9a9a3ed.png
fetch usagi weed-a 20260930/36cdd51347f86fe86f8c1bbf926b5ba5.png
fetch momonga idle-a 20260929/883889288decc2c14397295129c016f4.png
fetch momonga idle-b gif/44ec23965995aee793f9e9b0ce245e87.gif
fetch momonga walk-a 20260929/883889288decc2c14397295129c016f4.png
fetch momonga fall-a 20260929/db44a9c99a5c83b8c1e9911c7ec57506.png
fetch momonga react-b 20260929/843727d38a0f97589a45f6e38e8590cf.png
fetch momonga react-c 20260929/8348533a265950e6d75e5b3fb9906a45.png
fetch momonga eat-a 20260929/ddd00dfb2529ab87984e11a3c168b381.png
fetch momonga eat-b 20260929/12f3409ecf32966010caf2b612514edd.png
fetch momonga sleep-a 20260929/38e64a2fecea0d098ebabece973ff750.png
fetch momonga weed-a 20260929/dd58cefc05d4690380523bd748e6a468.png
fetch kurimanju idle-a 20260930/0d02273c2614b3e73404979ae0dde745.png
fetch shisa idle-a 20260930/968491f5caf502d2cd53dee9a9fc3bb8.png
fetch shisa idle-b 20260930/5b0c2100e140fe455285d267c388e488.png
fetch shisa react-a 20260930/d4bf2d912aef09863b024646516dede3.png
fetch shisa sleep-a 20260930/a3f35172c416344b276f108dcb6235bb.png
fetch shisa dance-a 20260930/5b0c2100e140fe455285d267c388e488.png
echo "완료: $dest"
