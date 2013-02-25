evest
=====

This script scrapes market data for any (or all) of the 5 trade hubs - jita, amarr, rens, dodixie, and hek. You give it a margin of profit that you would like between the highest buy order and the lowest sell order, and it generates a list of things that match your criteria.

It's best to run this in jruby (http://jruby.org/) to take advantage of JVM threading.

You need to install mongodb (http://www.mongodb.org/).

The following gems are required:

  -mongo
  
  -rest-client

You can install them with jruby like this:

  $> jruby -S gem install mongo
  
  $> jruby -S gem install rest-client

(-S runs the command following it on the CLI of the JVM)

Usage: (j)ruby evest.rb -m 1.0 systemID (profit margin defaults to 100% (1.0) - if you don't specify a systemid, it will scrape from the 5 major trade hubs)

Output usage: (j)ruby evest.rb -o > my_csv_name.csv

To drop all the data previously scraped from Mongo, run:

(j)ruby evest.rb -d

Donations appreciated to Slappy McSqueege McGillicuddy. I will help you get it running, guaranteed, for a 100 million isk donation.

Happy market PvPing!
