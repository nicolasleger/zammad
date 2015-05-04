# Copyright (C) 2012-2014 Zammad Foundation, http://zammad-foundation.org/

class LongPollingController < ApplicationController
  skip_filter :session_update

  # GET /api/v1/message_send
  def message_send
    new_connection = false

    # check client id
    client_id = client_id_verify
    if !client_id
      new_connection = true
      client_id = client_id_gen
      log 'new client connection', client_id
    end
    if !params['data']
      params['data'] = {}
    end

    # spool messages for new connects
    if params['data']['spool']
      msg = JSON.generate( params['data'] )
      Sessions.spool_create(msg)
    end

    # get spool messages and send them to new client connection
    if params['data']['action'] == 'spool'

      # error handling
      if params['data']['timestamp']
        log "request spool data > '#{Time.at( params['data']['timestamp'] )}'", client_id
      else
        log 'request spool init data', client_id
      end

      if current_user
        spool = Sessions.spool_list( params['data']['timestamp'], current_user.id )
        spool.each { |item|
          if item[:type] == 'direct'
            log "send spool to (user_id=#{ current_user.id })", client_id
            Sessions.send( client_id, item[:message] )
          else
            log 'send spool', client_id
            Sessions.send( client_id, item[:message] )
          end
        }
      end

      # send spool:sent event to client
      sleep 0.2
      log 'send spool:sent event', client_id
      Sessions.send( client_id, { event: 'spool:sent', data: { timestamp: Time.now.utc.to_i } } )
    end

    # receive message
    if params['data']['action'] == 'login'
      user_id = session[:user_id]
      user = {}
      if user_id
        user = User.find( user_id ).attributes
      end
      log "send auth login (user_id #{user_id})", client_id
      Sessions.create( client_id, user, { type: 'ajax' } )

      # broadcast
    elsif params['data']['action'] == 'broadcast'

      # list all current clients
      client_list = Sessions.list
      client_list.each {|local_client_id, local_client|
        if local_client_id != client_id

          # broadcast to recipient list
          if params['data']['recipient'] && params['data']['recipient']['user_id']
            params['data']['recipient']['user_id'].each { |user_id|
              if local_client[:user]['id'].to_s == user_id.to_s
                log "send broadcast from (#{client_id}) to (user_id #{user_id})", local_client_id
                Sessions.send( local_client_id, params['data'] )
              end
            }
            # broadcast every client
          else
            log "send broadcast from (#{client_id})", local_client_id
            Sessions.send( local_client_id, params['data'] )
          end
        else
          log 'do not send broadcast to it self', client_id
        end
      }
    end

    if new_connection
      result = { client_id: client_id }
      render json: result
    else
      render json: {}
    end
  end

  # GET /api/v1/message_receive
  def message_receive

    # check client id
    client_id = client_id_verify
    if !client_id
      render json: { error: 'Invalid client_id receive!' }, status: :unprocessable_entity
      return
    end

    # check queue to send
    begin

      # update last ping
      4.times {|loop|
        sleep 0.25
      }
      #sleep 1
      Sessions.touch( client_id )

      # set max loop time to 24 sec. because of 30 sec. timeout of mod_proxy
      count = 12
      while true
        count = count - 1
        queue = Sessions.queue( client_id )
        if queue && queue[0]
          logger.debug "send #{queue.inspect} to #{client_id}"
          render json: queue
          return
        end
        8.times {|loop|
          sleep 0.25
        }
        #sleep 2
        if count == 0
          render json: { action: 'pong' }
          return
        end
      end
    rescue Exception => e
      logger.error e.inspect
      logger.error e.backtrace
      render json: { error: 'Invalid client_id in receive loop!' }, status: :unprocessable_entity
      return
    end
  end

  private

  def client_id_gen
    rand(9_999_999_999).to_s
  end

  def client_id_verify
    return if !params[:client_id]
    sessions = Sessions.sessions
    return if !sessions.include?( params[:client_id].to_s )
    params[:client_id].to_s
  end

  def log( data, client_id = '-' )
    logger.info "client(#{ client_id }) #{ data }"
  end
end
