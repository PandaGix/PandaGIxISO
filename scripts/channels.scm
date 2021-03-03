(list
    (channel (inherit (car %default-channels))
        (url "https://git.nju.edu.cn/nju/guix.git")
        (commit "6941dbf958a2294e0a058af3498df9c46a6a1e50")
    ) ; end of (channel, guix
    (channel (name 'nonguix) 
            (url "https://git.nju.edu.cn/nju/nonguix.git")
            (commit "1d58ea1acadba57b34669c8a3f3d9f0de8d339b5") ; linux 5.4.98 5.10.16
            (introduction
		            (make-channel-introduction ; see https://gitlab.com/nonguix/nonguix
          	    "897c1a470da759236cc11798f4e0a5f7d4d59fbc"
          	    (openpgp-fingerprint
           	    "2A39 3FFF 68F4 EF7A 3D29  12AF 6F51 20A0 22FB B2D5"
    )))) ; end of (channel, nonguix   
) ; END of (list (channel
