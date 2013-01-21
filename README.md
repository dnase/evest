evest
=====

It's best to run this in jruby (http://jruby.org/) to take advantage of java threading.

You need to install mongodb (http://www.mongodb.org/).

The following gems are required:

mongo
rest-client

You can install them with jruby like this:
$> jruby -S gem install mongo
$> jruby -S gem install rest-client

(-S runs the command following it on the CLI of the JVM)