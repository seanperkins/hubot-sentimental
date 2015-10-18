# Description:
#   Calculate the average Sentimental / happiness score for each person based on their spoken words
#
# Dependencies:
#   "Sentimental": "0.0.4"
#   "redis": ">= 0.10.0"
#
# Configuration:
#   REDISTOGO_URL
#
# Commands:
#   hubot check on <username>
#   hubot check on everyone
#
# Notes:
#   All text spoken and not directed to hubot will be scored against the sentimental database
#    and a running average will be saved.
#   You can use the "check on" commands to look up current averages for the different users.

analyze = require('Sentimental').analyze
positivity = require('Sentimental').positivity
negativity = require('Sentimental').negativity

Url   = require "url"
Redis = require "redis"
_     = require "lodash"

module.exports = (robot) ->

# check for redistogo auth string for heroku users
# see https://github.com/hubot-scripts/hubot-redis-brain/issues/3
  info = Url.parse process.env.REDISTOGO_URL or process.env.REDISCLOUD_URL or process.env.BOXEN_REDIS_URL or process.env.REDIS_URL or 'redis://localhost:6379'
  if info.auth
    client = Redis.createClient(info.port, info.hostname, {no_ready_check: true})
    client.auth info.auth.split(":")[1], (err) ->
      if err 
        robot.logger.error "hubot-sentimental: Failed to authenticate to Redis"
      else
        robot.logger.info "hubot-sentimental: Successfully authenticated to Redis" 
  else
    client = Redis.createClient(info.port, info.hostname)

  robot.hear /(.*)/i, (msg) ->
    spokenWord = msg.match[1]
    if spokenWord and spokenWord.length > 0 and !new RegExp("^" + robot.name).test(spokenWord)
      analysis = analyze spokenWord
      username = msg.message.user.name

      client.get "sent:userScore", (err, reply) ->
        if err
          robot.emit 'error', err
        else if reply
          sent = JSON.parse(reply.toString())
        else
          sent = {}

        sent[username] = {score: 0, messages: 0, average: 0} if !sent[username] or !sent[username].average
        sent[username].score += analysis.score
        sent[username].messages += 1
        sent[username].average = sent[username].score / sent[username].messages

        client.set "sent:userScore", JSON.stringify(sent)

        if analysis.score < -2
          msg.send "stay positive #{msg.message.user.name}"

        robot.logger.debug "hubot-sentimental: #{username} now has #{sent[username].score} / #{sent[username].average}"

  robot.respond /check on (.*)/i, (msg) ->
    username = msg.match[1]
    client.get "sent:userScore", (err, reply) ->
      if err
        robot.emit 'error', err
      else if reply
        sent = JSON.parse(reply.toString())
        if username != "everyone" and (!sent[username] or sent[username].average == undefined)
          msg.send "#{username} has no happiness average yet"
        else
          combined = _.map(sent, (object, key) ->
            ret = {user: key}
            ret = _.merge(ret, object)
            return ret
          )
          sorted = _.sortByOrder(combined, 'average', 'desc')
          attachment = {
            fallback: "#{sorted[0].user} leads in happiness with #{_.round(sorted[0].average)}",
            text: 'Happiness Index',
            fields: [],
            color: 'good'
          }
          users = []
          averages = []
          for user, data of sorted
            if (data.user == username or username == "everyone") and data.average != undefined
              average = _.round(data.average, 2)
              users.push(data.user)
              averages.push(average)
          userField = {title: 'User', value: users.join('\n'), short: true}
          happinessField = {title: 'Rating', value: averages.join('\n'), short: true}
          attachment.fields.push(userField, happinessField)
          message = {attachments:[attachment]}
          console.log('In the logs?')
          console.log(message)
          msg.send(message)
      else
        msg.send "I haven't collected data on anybody yet"