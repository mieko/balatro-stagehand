if os.getenv('STAGEHAND_TOKEN') then
    require('balatro_stagehand.errors').install()
    require('balatro_stagehand.boot')
end
