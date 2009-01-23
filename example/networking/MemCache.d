/*******************************************************************************

        @file MemCache.d
        
        Copyright (c) 2004 Kris Bell
        
        This software is provided 'as-is', without any express or implied
        warranty. In no event will the authors be held liable for damages
        of any kind arising from the use of this software.
        
        Permission is hereby granted to anyone to use this software for any 
        purpose, including commercial applications, and to alter it and/or 
        redistribute it freely, subject to the following restrictions:
        
        1. The origin of this software must not be misrepresented; you must 
           not claim that you wrote the original software. If you use this 
           software in a product, an acknowledgment within documentation of 
           said product would be appreciated but is not required.

        2. Altered source versions must be plainly marked as such, and must 
           not be misrepresented as being the original software.

        3. This notice may not be removed or altered from any distribution
           of the source.

        4. Derivative works are permitted, but they must carry this notice
           in full and credit the original source.


                        ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        
        @version        Initial version, February 2006

        @author         Kris


*******************************************************************************/

module tango.net.memcache.MemCache;

private import  tango.io.Console;

private import  tango.core.Thread,
                tango.core.Exception;

private import  tango.io.stream.Lines,
                tango.io.stream.Buffer;

private import  tango.net.SocketConduit,
                tango.net.InternetAddress;

private import  Integer = tango.text.convert.Integer;


/*******************************************************************************

        Directive to include the winsock2 library

*******************************************************************************/

version (Win32)
         pragma (lib, "wsock32");


/******************************************************************************

******************************************************************************/

class MemCache : private Thread
{
        alias uint function (void[], uint=0) Hasher;

        private Hasher          hasher; 
        private Connection      hosts[];
        private bool            active;
        private uint            watchdog;

        /**********************************************************************
        
        **********************************************************************/
                
        this (char[][] hosts, Hasher hasher = &jhash, uint watchdog = 3)
        {
                super (&run);
                setHosts (hosts);      

                // save configuration
                this.watchdog = watchdog;
                this.hasher = hasher;

                // start the watchdog
                active = true;
                super.start;
        }

        /**********************************************************************
        
        **********************************************************************/
                
        void close ()
        {
                if (hosts)
                   {
                   foreach (Connection server; hosts)
                            server.close;
                   hosts = null;
                   }
        }

        /**********************************************************************
        
                Store the key and value

        **********************************************************************/
                
        bool set (void[] key, void[] value, int flags=0, int timeout=0)
        {       
                return select(key).put("set", key, value, flags, timeout);
        }

        /**********************************************************************
        
                Store the value if key does not already exist

        **********************************************************************/
                
        bool add (void[] key, void[] value, int flags=0, int timeout=0)
        {       
                return select(key).put("add", key, value, flags, timeout);
        }

        /**********************************************************************
        
                Store the value only if key exists

        **********************************************************************/
                
        bool replace (void[] key, void[] value, int flags=0, int timeout=0)
        {
                return select(key).put("replace", key, value, flags, timeout);
        }

        /**********************************************************************
        
                Remove the specified key and make key "invalid" for the 
                duration of timeout, causing add(), get() and remove() on
                the same key to fail within that period

        **********************************************************************/
                
        bool remove (void[] key, int timeout=0)
        {
                return select(key).remove(key, timeout);
        }

        /**********************************************************************

                VALUE <key> <flags> <bytes>\r\n
                <data block>\r\n

        **********************************************************************/

        bool get (void[] key, Buffer buffer)
        {       
                return select(key).get(key, buffer);
        }

        /**********************************************************************
        
        **********************************************************************/
                
        bool incr (void[] key, uint value)
        {
                uint result;
                return incr (key, value, result);
        }

        /**********************************************************************
        
        **********************************************************************/
                
        bool decr (void[] key, uint value)
        {
                uint result;
                return decr (key, value, result);
        }

        /**********************************************************************
        
        **********************************************************************/
                
        bool incr (void[] key, uint value, inout uint result)
        {
                return select(key).bump ("incr", key, value, result);
        }

        /**********************************************************************
        
        **********************************************************************/
                
        bool decr (void[] key, uint value, inout uint result)
        {
                return select(key).bump ("decr", key, value, result);
        }

        /**********************************************************************
        
        **********************************************************************/
        
        void status (void delegate (char[], char[][] list) dg)
        {
                foreach (Connection server; hosts)
                         server.status (dg);
        }

        /**********************************************************************
        
        **********************************************************************/
        
        Buffer buffer (uint size)
        {
                return new Buffer (size);
        }

        /**********************************************************************
        
        **********************************************************************/
                
        protected void setHosts (char[][] hosts)
        {
                auto conn = new Connection [hosts.length];     

                foreach (int i, char[] host; hosts)
                         conn[i] = new Connection (host);

                // set new list of connections
                this.hosts = conn;
                connect (conn);
        }

        /**********************************************************************
        
                Connection watchdog thread

        **********************************************************************/
                
        private void run ()
        {
                while (active)
                       try {
                           Thread.sleep (watchdog);
                           Cout ("testing connections ...").newline;
                           connect (hosts);
                           } catch (Exception e)
                                    Cout ("memcache watchdog: ") (e.toString).newline;
        }

        /**********************************************************************
        
        **********************************************************************/
                
        private Connection select (void[] key)
        {
                return hosts[hasher(key) % hosts.length];
        }

        /**********************************************************************
        
        **********************************************************************/
                
        private void connect (Connection[] hosts)
        {
                foreach (Connection c; hosts)
                         c.connect;
        }

        /**********************************************************************
        
        **********************************************************************/
        
        static class Buffer
        {
                private uint    extent;
                private void[]  content;
        
                /**************************************************************
                        
                **************************************************************/
        
                private this (uint size)
                {
                        this.content = new byte [size];
                }
        
                /**************************************************************
                        
                **************************************************************/
        
                bool expand (uint size)
                {
                        if (size > content.length)
                            content.length = size;
                        return true;
                }
        
                /**************************************************************
                        
                **************************************************************/
        
                void[] set (uint size)
                {
                        extent = size;
                        return get();
                }
        
                /**************************************************************
                        
                **************************************************************/
        
                void[] get ()
                {
                        return content [0..extent];
                }
        }

	/**********************************************************************
	
	        jhash() -- hash a variable-length key into a 32-bit value
	
	          k     : the key (the unaligned variable-length array of bytes)
	          len   : the length of the key, counting by bytes
	          level : can be any 4-byte value
	
	        Returns a 32-bit value.  Every bit of the key affects every bit of
	        the return value.  Every 1-bit and 2-bit delta achieves avalanche.
	
	        About 4.3*len + 80 X86 instructions, with excellent pipelining
	
	        The best hash table sizes are powers of 2.  There is no need to do
	        mod a prime (mod is sooo slow!).  If you need less than 32 bits,
	        use a bitmask.  For example, if you need only 10 bits, do
	
	                    h = (h & hashmask(10));
	
	        In which case, the hash table should have hashsize(10) elements.
	        If you are hashing n strings (ub1 **)k, do it like this:
	
	                    for (i=0, h=0; i<n; ++i) h = hash( k[i], len[i], h);
	
	        By Bob Jenkins, 1996.  bob_jenkins@burtleburtle.net.  You may use 
	        this code any way you wish, private, educational, or commercial.  
	        It's free.
	
	        See http://burlteburtle.net/bob/hash/evahash.html
	        Use for hash table lookup, or anything where one collision in 2^32 
	        is acceptable. Do NOT use for cryptographic purposes.
	
	**********************************************************************/
	
	static final uint jhash (void[] x, uint c = 0)
	{
	        uint    a,
	                b;
	
	        a = b = 0x9e3779b9; 
	
	        uint len = x.length;
	        ubyte* k = cast(ubyte *) x.ptr;
	
	        // handle most of the key 
	        while (len >= 12) 
	              {
	              a += *cast(uint *)(k+0);
	              b += *cast(uint *)(k+4);
	              c += *cast(uint *)(k+8);
	
	              a -= b; a -= c; a ^= (c>>13); 
	              b -= c; b -= a; b ^= (a<<8); 
	              c -= a; c -= b; c ^= (b>>13); 
	              a -= b; a -= c; a ^= (c>>12);  
	              b -= c; b -= a; b ^= (a<<16); 
	              c -= a; c -= b; c ^= (b>>5); 
	              a -= b; a -= c; a ^= (c>>3);  
	              b -= c; b -= a; b ^= (a<<10); 
	              c -= a; c -= b; c ^= (b>>15); 
	              k += 12; len -= 12;
	              }
	
	        // handle the last 11 bytes 
	        c += x.length;
	        switch (len)
	               {
	               case 11: c += (cast(uint)k[10]<<24);
	               case 10: c += (cast(uint)k[9]<<16);
	               case 9 : c += (cast(uint)k[8]<<8);
	               case 8 : b += (cast(uint)k[7]<<24);
	               case 7 : b += (cast(uint)k[6]<<16);
	               case 6 : b += (cast(uint)k[5]<<8);
	               case 5 : b += k[4];
	               case 4 : a += (cast(uint)k[3]<<24);
	               case 3 : a += (cast(uint)k[2]<<16);
	               case 2 : a += (cast(uint)k[1]<<8);
	               case 1 : a += k[0];
	               default:
	               }
	
	        a -= b; a -= c; a ^= (c>>13); 
	        b -= c; b -= a; b ^= (a<<8); 
	        c -= a; c -= b; c ^= (b>>13); 
	        a -= b; a -= c; a ^= (c>>12);  
	        b -= c; b -= a; b ^= (a<<16); 
	        c -= a; c -= b; c ^= (b>>5); 
	        a -= b; a -= c; a ^= (c>>3);  
	        b -= c; b -= a; b ^= (a<<10); 
	        c -= a; c -= b; c ^= (b>>15); 
	
	        return c;
	}
}


/******************************************************************************

******************************************************************************/

private class Connection
{
        private alias Lines!(char) Line;

        private char[]          host;           // original host address
        private Line            line;           // reading lines from server
        private Bin             input;          // input stream
        private Bout            output;         // output stream
        private SocketConduit   conduit;        // socket to server
        private InternetAddress address;        // where server is listening
        private bool            connected;      // currently connected?

        /**********************************************************************
        
        **********************************************************************/
                
        this (char[] host)
        {
                this.host = host;
                conduit = new SocketConduit;
                output = new Bout (conduit);
                input = new Bin (conduit);
                line = new Line (input);
                address = new InternetAddress (host);
        }
        
        /**********************************************************************
        
        **********************************************************************/
                
        private void connect ()
        {
                if (! connected)
                      try {
                          conduit.connect (address);
                          connected = true;
                          Cout ("connected to ") (host).newline;
                          } catch (Object o)
                                   Cout ("failed to connect to ") (host) .newline;
        }
        
        /**********************************************************************
        
        **********************************************************************/
                
        private synchronized void close ()
        {
                bool alive = connected;
                connected = false;

                if (alive)
                    conduit.close;
        }
        
        /**********************************************************************
        
        **********************************************************************/
                
        private void error ()
        {
                // close this dead socket
                close;

                // open another one for next attempt to connect
                conduit.socket.reopen;
        }

        /**********************************************************************
        
        **********************************************************************/
                
        private synchronized bool put (char[] cmd, void[] key, void[] value, int flags, int timeout)
        {
                if (connected)
                    try {
                        char[16] tmp;
                        
                        output.clear;
                        output.append ("delete ")
                              .append (key)
                              .append (" ")
                              .append (Integer.format (tmp, timeout))
                              .append ("\r\n")
                              .flush;

                        if (line.next)
                            return line.get == "DELETED";
                        } catch (IOException e)
                                 error;
                return false;
        }

        /**********************************************************************

                VALUE <key> <flags> <bytes>\r\n
                <data block>\r\n

        **********************************************************************/

        private synchronized bool get (void[] key, MemCache.Buffer buffer)
        {       
                if (connected)
                    try {
                        output.clear;
                        output.append ("get ")
                              .append (key)
                              .append ("\r\n")
                              .flush;
        
                        if (line.next)
                           {
                           char[] content = line.get;
                           if (content.length > 4 && content[0..5] == "VALUE")
                              {
                              int i;
        
                              // parse the incoming content-length
                              for (i=content.length; content[--i] != ' ';) 
                                  {}
                              i = Integer.parse (content[i .. $]);
        
                              // ensure output buffer has enough space
                              buffer.expand (i);
                              void[] dst = buffer.set (i);
        
                              // fill the buffer content
                              if (! input.fill (dst))
                                    return false;
        
                              // eat the CR and test terminator
                              line.next;
                              line.next;
                              return line.get == "END";
                              }
                           }
                        } catch (IOException e)
                                 error;
                return false;
        }

        /**********************************************************************
        
                Remove the specified key and make key "invalid" for the 
                duration of timeout, causing add(), get() and remove() on
                the same key to fail within that period

        **********************************************************************/
                
        private synchronized bool remove (void[] key, int timeout=0)
        {
                if (connected)
                    try {
                        char[16] tmp;
        
                        output.clear;
                        output.append ("delete ")
                              .append (key)
                              .append (" ")
                              .append (Integer.format (tmp, timeout))
                              .append ("\r\n")
                              .flush;
        
                        if (line.next)
                            return line.get == "DELETED";
                        } catch (IOException e)
                                 error;
                return false;
        }

        /**********************************************************************
        
        **********************************************************************/
                
        private synchronized bool bump (char[] cmd, void[] key, uint value, inout uint result)
        {
                if (connected)
                    try {
                        char[16] tmp;
        
                        output.clear;
                        output.append (cmd)
                              .append (" ")
                              .append (key)
                              .append (" ")
                              .append (Integer.format (tmp, value))
                              .append ("\r\n")
                              .flush;
        
                        if (line.next)
                            if (line.get != "NOT_FOUND")
                               {
                               result = Integer.parse (line.get);
                               return true;
                               }
                        } catch (IOException e)
                                 error;
                return false;
        }

        /**********************************************************************
        
        **********************************************************************/
        
        private synchronized void status (void delegate (char[], char[][] list) dg)
        {
                if (connected)
                    try {
                        char[][] list;

                        output.clear;
                        output.write ("stats\r\n");
        
                        while (line.next)
                               if (line.get == "END")
                                  {
                                  dg (host, list);
                                      break;
                                  }
                               else
                                  list ~= line.get;

                        } catch (IOException e)
                                 error;
        }

}       


debug (MemCache)
{
/******************************************************************************

******************************************************************************/

void main()
{
        static char[][] hosts = ["192.168.111.224:11211"];

        auto cache = new MemCache (hosts);

        cache.set ("foo", "bar");
        cache.set ("foo", "wumpus");

        auto buffer = cache.buffer (1024);
        if (cache.get ("foo", buffer))
            Cout ("value: ") (cast(char[]) buffer.get).newline;

        void stat (char[] host, char[][] list)
        {
                foreach (char[] line; list) 
                         Cout (host) (" ") (line).newline;
        }
        
        while (true)
              {
              cache.status (&stat);
              Thread.sleep (1.0);
              }
        Cout ("exiting");
}
}

