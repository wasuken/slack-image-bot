# coding: utf-8

require 'slack'
require 'open-uri'
require 'faraday'
require 'fileutils'
require 'thor'
require 'sqlite3'
require 'parseconfig'


CONFIG = ParseConfig.new("config")
SLACK_TOKEN = CONFIG["slack-token"]
G_KEY = CONFIG["g-key"]
G_SITE_KEY = CONFIG["g-site-key"]
# RTM Clientのインスタンス生成
CLIENT = Slack::Client.new token: SLACK_TOKEN
DB = SQLite3::Database.new CONFIG["db-path"]
DB.results_as_hash = true

Slack.configure do |config|
  config.token = SLACK_TOKEN
end

#この2つのメソッド抽象化できる気がする
## dirnameをテーブルに追加し、さらにそのIDを返す
def insert_dirname_and_return_Id(dirname)
  DB.execute('insert into image_dirpath(dirname) values(?)',dirname)
  return DB.execute('select d_id from image_dirpath where dirname = ?',dirname).first[0]
end
## filenameをテーブルに追加する。
def insert_filename(filename,d_id)
  cnt = DB.execute('select f_id from image_filepath where d_id = ?',d_id).count + 1
  DB.execute('insert into image_filepath(f_id,d_id,filename) values(?,?,?)',cnt,d_id,filename)
end

#既に存在するものをアップロードする処理へと変更する。なければDLみたいな
#カレントディレクトリの下に保存するの辛そうなんで
#せめてパスはDBに保存するべきでは
def store(dir_path, image_url)
  p "DL開始"
  FileUtils.mkdir_p(dir_path)
  p image_url
  d_id = insert_dirname_and_return_Id(dir_path)
  image_url.each do |url|
    filename = "#{dir_path}/#{File.basename(url)}"
    insert_filename(File.basename(url),d_id)
    open(filename, 'wb') do |file|
      open(url) do |data|
        file.write(data.read)
      end
    end
  end
  p 'DL完了'
end

def upload_dirimages(name,num,roomName)
  DB.execute('select dirname, filename from image_dirpath d join image_filepath f on f.d_id = d.d_id where dirname = ?',name).slice(0,num).each do |row|
    filename = "#{row["dirname"]}/#{row["filename"]}"
    CLIENT.files_upload(
      channels: "##{roomName}",
      as_user: true,
      file: Faraday::UploadIO.new(filename,filename),
      filename: row["filename"],
      initial_comment: row["filename"]
    )
  end
end
def parseMsg(msg)
  repAry = {"\b" => " "," "=>"+","　" => "+"}
  repAry.each{|k,v| msg = msg.gsub(k,v)}
  msg
end
def imageUploadToSlack(query,num = 3,roomName = "general")
  cnt = DB.execute('select * from image_dirpath where dirname = ? limit 1',query).count
  if cnt <= 0
    url = "https://www.googleapis.com/customsearch/v1?key=#{G_KEY}&cx=#{G_SITE_KEY}&q=#{query}&searchType=image"
    conn = Faraday.new(url: URI.encode(url))
    response = conn.get
    result = JSON.parse(response.body)
    image_url = result["items"].map {|item| item["link"] }
    store(query, image_url)
  end
  upload_dirimages(query,num,roomName)
end

rtm = CLIENT.realtime
rtm.on :message do |m|
  p m
  if m["text"] == nil
    next
  end
  #google api key:AIzaSyBTs1ycp6lHSC36-G_FdcyoN631KbWCzBQ
  #google custom site api key:012669513796817398149:to81ftrqtnm
  qSp = parseMsg(m["text"]).split(":")
  p qSp
  if m["user"] == CONFIG["bot-user"] && (m["channel"] == CONFIG["bot-channel-1"] ||
                                  m["channel"] == CONFIG["bot-channel-2"]) && qSp.first == "image" then
    # <image>:<検索文字列>:[数]:[channel]
    # ものすごい辛い作りだがこれどうにかできないのか
    case qSp.count
    when 2 then
      imageUploadToSlack(qSp[1])
    when 3 then
      imageUploadToSlack(qSp[1],(qSp[2].to_i))
    when 4 then
      imageUploadToSlack(qSp[1],qSp[2].to_i,qSp[3])
    end
  end
end
rtm.start
