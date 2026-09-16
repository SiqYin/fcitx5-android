cmake_minimum_required(VERSION 3.18)

project(fcitx5-android-plugin-rime VERSION ${VERSION_NAME})

# For reproducible build
add_link_options("LINKER:--hash-style=gnu,--build-id=none")

# prefab dependency
find_package(fcitx5 REQUIRED CONFIG)
get_target_property(FCITX5_CMAKE_MODULES fcitx5::cmake INTERFACE_INCLUDE_DIRECTORIES)
set(CMAKE_MODULE_PATH ${FCITX5_CMAKE_MODULES} ${CMAKE_MODULE_PATH})

find_package(ECM MODULE)
find_package(Fcitx5Core MODULE)
find_package(Fcitx5Module MODULE)

set(Rime_VERSION "1.12.0")
set(Rime_dependencies
        log # glog links to android log
        "${PREBUILT_DIR}/glog/${ANDROID_ABI}/lib/libglog.a"
        "${PREBUILT_DIR}/leveldb/${ANDROID_ABI}/lib/libleveldb.a"
        "${PREBUILT_DIR}/lua/${ANDROID_ABI}/lib/liblua_static.a"
        "${PREBUILT_DIR}/marisa/${ANDROID_ABI}/lib/libmarisa.a"
        "${PREBUILT_DIR}/opencc/${ANDROID_ABI}/lib/libopencc.a"
        "${PREBUILT_DIR}/yaml-cpp/${ANDROID_ABI}/lib/libyaml-cpp.a"
        )

add_library(Rime_static STATIC IMPORTED)
set_target_properties(Rime_static PROPERTIES
        IMPORTED_LOCATION "${PREBUILT_DIR}/librime/${ANDROID_ABI}/lib/librime.a"
        INTERFACE_INCLUDE_DIRECTORIES "${PREBUILT_DIR}/librime/${ANDROID_ABI}/include"
        INTERFACE_LINK_LIBRARIES "${Rime_dependencies}"
        )

# https://github.com/rime/librime/blob/1.9.0/src/rime_api.h#L663
# https://stackoverflow.com/questions/805555/ld-linker-question-the-whole-archive-option
# https://cmake.org/cmake/help/latest/manual/cmake-generator-expressions.7.html#link-features
set(RIME_TARGET $<LINK_LIBRARY:WHOLE_ARCHIVE,Rime_static>)
set(RIME_DATA_DIR "${CMAKE_INSTALL_DATADIR}/rime-data")
add_subdirectory(fcitx5-rime)

install(FILES
        "default.yaml"
        "rime-essay/essay.txt"
        "rime-prelude/key_bindings.yaml"
        "rime-prelude/punctuation.yaml"
        "rime-prelude/symbols.yaml"
        "rime-luna-pinyin/luna_pinyin_fluency.schema.yaml"
        "rime-luna-pinyin/luna_pinyin_simp.schema.yaml"
        "rime-luna-pinyin/luna_pinyin_tw.schema.yaml"
        "rime-luna-pinyin/luna_pinyin.dict.yaml"
        "rime-luna-pinyin/luna_pinyin.schema.yaml"
        "rime-luna-pinyin/luna_quanpin.schema.yaml"
        "rime-luna-pinyin/pinyin.yaml"
        "rime-stroke/stroke.dict.yaml"
        "rime-stroke/stroke.schema.yaml"
        DESTINATION "${FCITX_INSTALL_DATADIR}/rime-data"
        COMPONENT prebuilt-assets
        )

# wugniu_suwu (吴语混合腔) scheme files
install(FILES
        "rime-wugniu-suwu/wugniu_suwu.schema.yaml"
        "rime-wugniu-suwu/wugniu_suwu.dict.yaml"
        "rime-wugniu-suwu/wuphin.word.dict.yaml"
        "rime-wugniu-suwu/wuphin.map.dict.yaml"
        "rime-wugniu-suwu/wuphin.phrases.dict.yaml"
            "rime-wugniu-suwu/sougouciku.dict.yaml"
        "rime-wugniu-suwu/symbols_wu.yaml"
        "rime-wugniu-suwu/wugniuji.ico"
        "rime-wugniu-suwu/wugniuji.png"
        DESTINATION "${FCITX_INSTALL_DATADIR}/rime-data"
        COMPONENT prebuilt-assets
        )

# wugniu_suwu OpenCC config files
# NOTE: TSCharacters.ocd2 / TSPhrases.ocd2 由本体提供（usr/share/opencc），
#       插件重复安装会与 Main 的路径冲突，导致整个插件数据被跳过（Rime 无法加载）。
#       本体已通过符号链接 usr/share/rime-data/opencc -> usr/share/opencc 提供给 rime 使用。
install(FILES
        "rime-wugniu-suwu/opencc/s2sy.json"
        "rime-wugniu-suwu/opencc/s2wy.json"
        "rime-wugniu-suwu/opencc/t2sy.json"
        "rime-wugniu-suwu/opencc/t2wy.json"
        "rime-wugniu-suwu/opencc/SWCharacters.txt"
        "rime-wugniu-suwu/opencc/SWPhrases.txt"
        "rime-wugniu-suwu/opencc/SYCharacters.txt"
        "rime-wugniu-suwu/opencc/TSCharacters.txt"
        "rime-wugniu-suwu/opencc/TSPhrases.txt"
        "rime-wugniu-suwu/opencc/TSCharacters.ocd"
        "rime-wugniu-suwu/opencc/TSPhrases.ocd"
        DESTINATION "${FCITX_INSTALL_DATADIR}/opencc"
        COMPONENT prebuilt-assets
        )
