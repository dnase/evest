#!/usr/bin/env jruby

require 'rubygems'
require 'mongo'
require 'date'
require 'rest_client'
require 'rexml/document'

include Mongo

@client = MongoClient.new('localhost', 27017)
@db     = @client['evestdb']
$coll   = @db['market_data']

$thread_dispatcher = Array.new

$systems	= {
	30002510	=> "Rens",
	30000142	=> "Jita",
	30002659	=> "Dodixie",
	30002187	=> "Amarr",
	30002053	=> "Hek"
}

$margin = 1.0

#add the is_number? function to the String class so that we can check if command line arguments are a valid number.
class String
  def is_number?
    true if Float(self) rescue false
  end
end

def output (coll)
	puts "ID,SYSTEM,TYPEID,NAME,CONTENT_TYPE,BUY_MAX_PRICE,SELL_MIN_PRICE,BUY_VOLUME,SELL_VOLUME,GROSS,SPREAD\n"
	coll.find({"content_type" => "market_record"}, :sort => ["spread", Mongo::DESCENDING] ).each { |r|
		mystr = ""
		r["systemid"] = $systems[r["systemid"]]
		r.each { |k, e|
			mystr += "\"" + e.to_s + "\","
		}
		puts mystr + "\n"
	}
	exit
end

def fetch_evecentral_marketstat (typeid, sysid)
	#wrapper func to handle caching and QoS
	if $coll.find({"typeid" => typeid, "systemid" => sysid}).to_a.empty?
		response = RestClient.get('http://api.eve-central.com/api/marketstat', {:params => {:typeid => typeid, :usesystem => sysid}, "User-Agent" => "Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.17 (KHTML, like Gecko) Chrome/24.0.1312.52 Safari/537.17"}) rescue nil
		if response
			return response
		else
			sleep 0.1
			return fetch_evecentral_marketstat(typeid, sysid)
		end
	else
		#cached = $coll.find_one({"typeid" => typeid, "systemid" => sysid})
		#puts cached.inspect
		#already got it
		return nil
	end
end

def process_data (response, name, typeid, col, sysid)
	#lambdas
	f = lambda { |s_p, b_p| ( s_p / b_p ) - 1 } #spread
	q = lambda { |a, b, c, d| (a * b * c * d) > 0 } #check for 0
	g = lambda { |b_v, b_p, s_v, s_p| ( b_v * b_p ) + ( s_v * s_p ) } #gross
	y = lambda { |x| ( x * 100 ).to_i }
	#vars
	buy_max_price	= 0.0
	sell_min_price	= 0.0
	buy_volume		= 0
	sell_volume		= 0
	if response && response.code == 200 
		#parse the XML response
		doc = REXML::Document.new(response.to_str)
		#there is only one of each of these.
		doc.elements.each('evec_api/marketstat/type/buy/max'){ |e| buy_max_price = e.text.to_f}
		doc.elements.each('evec_api/marketstat/type/sell/min'){ |e| sell_min_price = e.text.to_f}
		doc.elements.each('evec_api/marketstat/type/buy/volume'){ |e| buy_volume = e.text.to_f}
		doc.elements.each('evec_api/marketstat/type/sell/volume'){ |e| sell_volume = e.text.to_f}
		gross = g.call(buy_volume, buy_max_price, sell_volume, sell_min_price)				
		vol = sell_volume + buy_volume
		#if all values are over zero and it grosses over a billion isk a day in trade, store the data
		if q.call(buy_volume, sell_volume, buy_max_price, sell_min_price) && gross > 1000000000 #&& vol > 1000 && sell_volume > buy_volume
			#f is the split
			spread = f.call(sell_min_price, buy_max_price)
			readablespread = y.call(spread)
			if spread >= $margin
				#prep the data for mongo
				rec = {
					:systemid			=> sysid,
					:TypeID			=> typeid,
					:name				=> name,
					"content_type"		=> "market_record",						
					"buy_max_price"		=> buy_max_price, 
					"sell_min_price"	=> sell_min_price,
					"buy_volume"		=> buy_volume,
					"sell_volume"		=> sell_volume,
					"gross"				=> gross,
					"spread"			=> spread,
					"timestamp"			=> Time.now
				}
				rec[:system_id]
				#if a record for this typeid doesn't exist, insert one.
				if col.find({"typeid" => typeid, "systemid" => sysid}).to_a.empty?
					id = col.insert(rec)
					puts "INSERTED: system - #{$systems[sysid]}	spread - #{readablespread}%	name - #{name}\n"
				#otherwise, update the existing record.
				else
					col.update({"typeid" => typeid, "systemid" => sysid}, rec)
					puts "UPDATED: system - #{$systems[sysid]}	spread - #{readablespread}%	name - #{name}\n"
				end
			else
				#clean out any that have fallen outside the parameters
				col.remove({"typeid" => typeid, "systemid" => sysid})
				puts "ignored: sys - #{$systems[sysid]}	lo_sprd	name - #{name}\n"						
				end
		else
			#clean out any that have fallen outside the parameters - hate duplicating code, but whatever.
			col.remove({"typeid" => typeid, "systemid" => sysid})
			puts "ignored: sys - #{$systems[sysid]}	lo_vol	name - #{name}\n"
		end
	end
end

tmp = nil

ARGV.each_with_index{ |a, i|
	if a == "-o"
		output($coll)
	end
	if a == "-d"
		$coll.remove
		exit
	end 
	if a== "-m"
		$margin = ARGV[i + 1].to_f
	end
	if $systems.keys.include?(a.to_i)
		tmp.push({ a.to_i => $systems[a.to_i] }) rescue tmp = { a.to_i => $systems[a.to_i] }
	end
}

if tmp
	arr_systems = tmp
else
	arr_systems = $systems
end
arr_systems.keys.shuffle.each{ |system|
	#typeid.txt should contain one item per line, in the format: TypeID,Item Name
	farray = File.open('typeid.txt').to_a
	farray.shuffle! #randomize item order so we're more likely to find something interesting
	farray.each{ |line|
		#split with regex around comma to allow for ", " " , " etc.
		data = line.split(/\s*?,\s*?/)
		#remove any surrounding whitespace or linebreaks
		name = data[1].strip rescue false
		typeid = data[0].strip
		#query eve-central API
		response = fetch_evecentral_marketstat(typeid, system)
		#spawn a new thread to process the response, and toss it on the thread stack.
		$thread_dispatcher.push(Thread.new{process_data(response, name, typeid , $coll, system)})
	}
}


$thread_dispatcher.each{ |t|
	#join back all the child threads
	t.join
}
