Red [
	Title: "ChatWorkKeeper"
	Needs: 'View
	Author: "Koba-yu"
]

descape: func [
	"ユニコードエスケープシーケンス１文字をデコードします"
    code [integer!]	"エスケープシーケンスが示すコードポイント"
    /local raise-error low high
] [
	raise-error: [cause-error 'script 'invalid-arg form code]
	case [
		code < 0 [do raise-error]
		code < 65536 [append copy "" to char! code]
		code < 1114112 [
			code: code - 65536
			low: code and 1023
			high: code - low / 1024
			append append copy "" to char! high + 55296 to char! low + 56320
		]
		'else [do raise-error]
	]
]

decode: func [
		"ユニコードエスケープされた文字列をデコードします"
		string [string!]	"エスケープされた文字列"
		/local hex-char sequence
	][
	hex-char: charset [#"a" - #"z" #"0" - #"9"]
	rejoin parse string [collect [any [
				"\u" copy sequence [4 hex-char] keep (either p: debase/base sequence 16 [descape to-integer p][sequence])
				| keep skip
			]
		]
	]
]

hide-key: func [
	"コード／文字列のAPIキー部分を「XXXX」に変換して返します"
	api-key	[string!]	"APIキー"
	code
][
	load replace/deep mold copy code api-key "XXXX"
]

on-error: func [
	"errorの内容をログとして書込みします。書込み先は %temp%/ChatWorkKeeper/ です"
	api-key	[string!]	"APIキー"
	error				"エラー内容"
	/local n path folder
][
	attempt [
		n: now/precise
		path: replace/all rejoin [
			folder: rejoin [to-red-file dirize get-env "temp" 'ChatWorkKeeper "/"]
			n/date "-" pad/left/with n/time/hour 2 #"0" pad/left/with n/time/minute 2 #"0" take/part mold n/time/second 7 ".log"
		] ":" "-"
		unless exists? folder [create-dir folder]
		save path hide-key api-key error
	]

	error
]

handle: func [
	"write/infoのresponseデータを処理します。戻り値は最終的なhttpレスポンスコードです。"
	response	[block!]	"write/infoのresponseデータ"
	code 		[block!]	"リトライ用コード"
	/local reset-time response*
][
	switch/default response/1 [
		200 [200]
		204 [204]
		429 [
			try [
				reset-time: (to-date to-integer response/2/X-RateLimit-Reset) + 0:0:1
				wait difference reset-time now/utc
				response*: do code
				response*/1
			]
		]
	][
		response/1
	]
]

download: func [
	"ChatWork APIを使い、メッセージとファイルをダウンロードします"
	api-key		[string!]	"APIキー"
	destination [file!]		"書込み先フォルダ"
	/local error code response maps map room-id json message-folder result file-folder saved-files file x file-id
][
	error: try [
		result: get-rooms api-key
		unless result/success? [on-error api-key result return false]

		result: save-rooms destination result/json
		unless result/success? [on-error api-key result return false]
		room-ids: result/room-ids

		foreach room-id room-ids [

			message-folder: rejoin [destination "messages/"]

			if message-converted? message-folder room-id [continue]

			result: get-messages api-key room-id

			case [
				result/status = 'empty [continue]
				result/status = 'error [on-error api-key result continue]
			]
			json: result/json

			result: save-messages room-id json message-folder
			unless result/success? [on-error api-key result continue]

			convert-message room-id json message-folder
		]

		file-folder: rejoin [destination "files/"]
		unless exists? file-folder [create-dir file-folder]
		saved-files: make hash! collect [foreach file read file-folder [
				x: take/part split form file "-" 2	; "-" で分割
				x: head insert at x 2 "-"			; 2番目に "-" を入れてインデックスを先頭に戻す
				keep rejoin x
			]
		]

		foreach room-id room-ids [
			result: file-ids? api-key room-id

			case [
				result/status = 'empty [continue]
				result/status = 'error [on-error api-key result continue]
			]

			foreach file-id result/file-ids [

				if find saved-files rejoin [room-id "-" file-id] [continue]

				result: get-url api-key room-id file-id
				unless result/success? [on-error api-key result continue]

				result: download-file result/url rejoin [file-folder room-id "-" file-id "-" result/filename]
				unless result/success? [on-error api-key result]
			]
		]

		return object [success?: true]
	]

	; elseに入ることはないはずだが念のため
	case [
		error? error [ on-error api-key object compose [success?: false error: (error) room-id: (either value? room-id [room-id][none]) last-result: result file-id: (either value? file-id [file-id][none])] ]
		'else        [ 					object		   [success?: true] ]
	]
]

get-rooms: func [
	"自分のチャット一覧を取得します"
	api-key	[string!] "APIキー"
	/local error code response
][
	error: try code: compose/deep [
		response: write/info https://api.chatwork.com/v2/rooms [
			get [X-ChatWorkToken: (api-key)]
		]
	]

	object case [
		error? error					[ compose [success?: false error: (error) code: (code)] ]
		(handle response code) <> 200	[ compose [success?: false error: make error! "Response not 200" response: (response) code: (code)] ]
		'else							[ compose [success?: true  json: response/3]]
	]
]

save-rooms: func [
	"チャット一覧のJSONを保存します"
	destination	[file!]		"書込み先フォルダ"
	json		[string!]	"チャット一覧のJSON"
	/local maps map
][
	error: try [
		save rejoin [destination "rooms.json"] json
		maps: load/as json 'json
		save rejoin [destination "rooms.red"] maps
		'ok
	]

	object case [
		error? error	[ compose [success?: false error: (error)] ]
		'else 			[ 		  [success?: true room-ids: collect [foreach map maps [keep map/room_id]]] ]
	]
]

message-converted?: func [
	"メッセージがダウンロード済みか確認します"
	message-folder	[file!]		"出力フォルダ"
	room-id			[integer!]	"チャットID"
][
	exists? path-to-convert? message-folder room-id
]

path-to-convert?: func [
	"メッセージ変換の出力先ファイルパスを返します"
	message-folder	[file!]		"出力フォルダ"
	room-id			[integer!]	"チャットID"
][
	rejoin [message-folder "message-" room-id ".red"]
]

get-messages: func [
	"チャットに紐づくメッセージを取得します"
	api-key		[string!]	"APIキー"
	room-id 	[integer!]	"チャットID"
	/local error code response
][
	; メッセージの取得
	error: try code: compose/deep [
			response: write/info to-url rejoin [https://api.chatwork.com/v2/rooms/ (room-id) "/messages?force=1"][
			get [X-ChatWorkToken: (api-key)]
		]
	]

	object case [
		error? error					[ compose [status: 'error error: (error) code: (code)] ]
		(handle response code) = 204	[ compose [status: 'empty] ]
		(handle response code) <> 200	[ compose [status: 'error error: make error! "Response not 200" response: (response) code: (code)] ]
		'else							[		  [status: 'ok    json:  response/3] ]
	]
]

save-messages: func [
	"メッセージのJSONをローカルに保存します"
	room-id			[integer!]	"チャットID"
	json			[string!]	"メッセージのJSON"
	message-folder	[file!]		"メッセージ出力フォルダ"
	/local error
][
	error: try [
		unless exists? message-folder [create-dir message-folder]
		save rejoin [message-folder "message-" room-id ".json"] json
		'ok
	]

	object case [
		error? error	[ compose [success?: false error: (error)] ]
		'else 			[ 		  [success?: true] ]
	]
]

convert-message: func [
	"メッセージのJSONをmap!に変換して保存します"
	room-id			[integer!]	"チャットID"
	json			[string!]	"メッセージのJSON"
	message-folder	[file!]		"メッセージ出力フォルダ"
	/local error code maps map
][
	error: try code: [
		maps: load/as json 'json
		foreach map maps [map/body: decode map/body]
		save path-to-convert? message-folder room-id maps
		'ok
	]

	object case [
		error? error	[ compose [success?: false error: (error) code: (code) maps: (maps) map: (map)] ]
		'else 			[		  [success?: true] ]
	]
]

file-ids?: func [
	"チャットに紐づくファイルのIDのリスト（block!）を取得します"
	api-key		[string!]	"APIキー"
	room-id		[integer!]	"チャットID"
	/local error code response int
][
	; ファイル一覧を取得
	error: try code: compose/deep [
			response: write/info to-url rejoin [https://api.chatwork.com/v2/rooms/ (room-id) "/files"][
			get [X-ChatWorkToken: (api-key)]
		]
	]

	; 添付ファイルが1つもないと204が返る
	object case [
		error? error					[ compose [status: 'error error: (error) code: (code)] ]
		(handle response code) = 204	[ compose [status: 'empty] ]
		(handle response code) <> 200	[ compose [status: 'error error: make error! "Response not 200" response: (response) code: (code)] ]
		'else							[		  [status: 'ok  file-ids: do [
					int: charset [#"0" - #"9"]
					parse response/3 [collect [any [thru {"file_id":} keep some int]]]
				]
			]
		]
	]
]

get-url: func [
	"ファイルダウンロード用のURLを取得します"
	api-key	[string!]	"APIキー"
	room-id	[integer!]	"チャットID"
	file-id	[string!]	"ファイルID"
	/local error code response map
][
	code: compose/deep [
		response: write/info to-url rejoin [
			https://api.chatwork.com/v2/rooms/ (room-id) "/files/" (file-id) "?create_download_url=1"
		][get [X-ChatWorkToken: (api-key)]]
	]

	error: try code
	c: handle response code
	map: load/as response/3 'json

	object case [
		error? error	[ compose [success?: false error: (error) code: (code)] ]
		c = 200			[		  [success?: true  url: to-url map/download_url filename: map/filename] ]
		c = 204			[ compose [success?: true  code: (code) response: (response)] ]
		'else			[ compose [success?: false error: c code: (code) response: (response)] ]
	]
]

download-file: func [
	"ファイルをダウンロードします"
	url			[url!]	"ダウンロードURL"
	destination	[file!]	"書込みファイル名のフルパス"
	/local file writing file-folder
][
	loop 12 [
		file: try [read/binary url]
		unless error? file [break]
		wait 0:0:5
	]

	unless error? file [
		writing: try [
			file-folder: first split-path destination
			unless exists? file-folder [create-dir file-folder]
			write destination file
			'ok
		]
	]

	object case [
		error? file		[ [success?: false error: file] ]
		error? writing	[ [success?: false error: writing] ]
		'else			[ [success?: true] ]
	]
]

view/options [
	panel 100x120 [
		pad 0x5 text "ChatWork APIキー"	return
		pad 0x5 text "保存先フォルダ" return
		pad 0x5 b: button "実行" [
			b/enabled?: false

			unless exists? folder: to-red-file dirize folder/text [create-dir folder]
			destination: to-red-file rejoin [folder "chatwork-backup/"]
			unless exists? destination [create-dir destination]

			result: try [download key/text destination]
			alert either result/success? ["処理が終了しました。"]["エラーが発生しました。"]
			unview
		]
	]
	panel 330x120 [
		key: field 300x30 password return
		folder: field 300x30
	]
][text: "ChatWorkKeeper"]