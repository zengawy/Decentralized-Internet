// This file is part of the GridBee Web Computing Framework
// <http://webcomputing.iit.bme.hu>
// Copyright 2011 Budapest University of Technology and Economics,
// Public Administration's Centre of Information Technology (BME IK)
//
// GridBee is free software: you can redistribute it and/or modify
// it under the terms of the GNU Lesser General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// GridBee is distributed in the hope that it will be useful
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Lesser General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with GridBee. If not, see <http://www.gnu.org/licenses/>.

package gridbee.core.work;

import gridbee.core.iface.Worker;
import gridbee.worksource.boinc.reply.Message;
import haxe.Log;
import js.Dom;
import js.Lib;
import gridbee.core.work.hxjson2.JSON;
import gridbee.core.iface.Worker;
import henkolib.log.Console;

/**
 * ...
 * @author Kalmi
 */

/*
 * NaClWorker is wrapper around NaCl that makes it act like a WebWorker.
 * 
 * Usage:
 *   Use it just like you would use a WebWorker,
 *   and it will transparently JSON encode/decode
 *   communcation between your Haxe code and the NaCl module.
 * 
 * Ports are not supported.
 * 
 * WARNING: The NaClWorker uses haxe's getters and setters, which don't get translated into Javascript as such.
 *          You should not use this from Javascipt, only from Javascript generated by Haxe.
 *          It would work to some extent when used from Javascript not generated by Haxe,
 *          but errors and messages could get lost in edge cases,
 * 	        such as errors occuring while loading NaCl modules,
 *          which would result in your code not getting notified of the crash
 *          and your code believing that NaCl is loading forever...
 */
class NaClWorker extends NaClWorker_StringOnly, implements Worker
{
	public static function isSupported():Bool {
		return NaClWorker_StringOnly.isSupported();
	}
  
	private override function _onmessage(evt: MessageEvent) : Void {	
		//Log.trace("_onmessage JSON wrapper called with " + evt.data);
		super._onmessage(evt);
	}
  
	public override function postMessage(message:Dynamic) {
		//Log.trace("postMessage JSON wrapper called with " + message);    
		message = JSON.encode(message); //FIXME: error handling
		super.postMessage(message);
	}
	
	public function setOnerror(func : ErrorEvent -> Void) : Void
	{
		onerror = func;
	}
	
	public function setOnmessage(func : MessageEvent -> Void) : Void
	{
		onmessage = func;
	}
}


private class NaClWorker_StringOnly
{
  var outerIframe : Dynamic;
  var innerIframe : Dynamic;
	
  public var onerror(default,default) : ErrorEvent -> Void; //Not used. We only use exception type messages.
  
	/* onmessage(MessageEvent):Void;
	 * We queue the messages coming from NaCl until the user of the class assigns something to onmessage.
	 * It is neccasary because exception type messages can occur right after loading the module.
	 */	
	var onmessageQueue : List<MessageEvent>; //Queue messages until user sets onmessage
	public var onmessage (onmessageGetter , onmessageSetter): MessageEvent -> Void; //This is what gets set by the user. Its setter sends the contents of its queue to it.
	private var onmessageTheRealOne : MessageEvent -> Void; //The internal variable that gets set/read by the getter/setter.
	private function onmessageSetter(func : MessageEvent -> Void) : MessageEvent -> Void {		
		//Log.trace("onmessageSetter called");
		if (func != null) {			
			if (!onmessageQueue.isEmpty())
			{
				//Log.trace("  sending content of queue");
			}
			var evt : MessageEvent;
			while ((evt = onmessageQueue.pop()) != null) { 
				//Log.trace("    sent");
				func(evt);
			}
			this.onmessageTheRealOne = func;
		}	
		return func;
	}
	private function onmessageGetter(): MessageEvent -> Void {
		return this.onmessageTheRealOne;
	}
	
	private function ParseEventData(evt : MessageEvent) : MessageEvent
	{
		var simpleEvent = new SimpleMessageEvent();
		simpleEvent.lastEventId = evt.lastEventId;
		simpleEvent.origin = evt.origin;
		simpleEvent.type = evt.type;
		try {
			simpleEvent.data = JSON.parse(evt.data);
		}catch (unknown : Dynamic) {
			simpleEvent.data = JSON.parse('{"command": "exception", "exception" : { "message" : "Got invalid JSON from NaCl. NaCl termined." }}');
		}
		return simpleEvent;
	}
	
	private function _onmessage(evt: MessageEvent) : Void {	
		//Log.trace("_onmessage called");
		if (evt.data == "READY") {
			this.isReady = true;
			//NaCl became ready -> Send queued messages
			var message : String;
			while ((message = postMessageQueue.pop())!=null) { 
			  innerIframe.contentWindow.postMessage(message,"*");
			}
		} else if (this.onmessage != null) {
				//Log.trace("  handing it off to onmessage");
				this.onmessage(ParseEventData(evt));
		} else {
		  //Log.trace("  queueing it");
		  onmessageQueue.add(evt);
		}
	}
	
	public var isReady(default, null) : Bool;
	
	public static function isSupported():Bool {		
		var testNaclElement:Dynamic = js.Lib.document.createElement("embed");
		testNaclElement.setAttribute("type", "application/x-nacl");
		testNaclElement.setAttribute("width",0);
		testNaclElement.setAttribute("height",0);		
		js.Lib.document.body.appendChild(testNaclElement);	
		var isSupported : Bool = testNaclElement.postMessage ? true : false;
		js.Lib.document.body.removeChild(testNaclElement);
		return isSupported;	
	}
	
	//Support for NaCl should be checked with isSupported before trying to create a new instance
	public function new(url : String) : Void {
		this.isReady = false;		
		this.postMessageQueue = new List<String>();
		this.onmessageQueue = new List<MessageEvent>();
		this.outerIframe = js.Lib.document.createElement("iframe");
		this.outerIframe.setAttribute("width",0);
		this.outerIframe.setAttribute("height",0);
		js.Lib.document.body.appendChild(this.outerIframe);
		
		this.innerIframe = js.Lib.document.createElement("iframe");
		this.innerIframe.setAttribute("src", url);
		
		this.outerIframe.contentWindow.document.body.appendChild(this.innerIframe);    
		this.outerIframe.contentWindow.addEventListener("message", this._onmessage, false);    			
	}
	
	// TODO?: messagePort
		
	var postMessageQueue : List<String>; //Queue messages until NaCl becomes ready
	public function postMessage(message : Dynamic /*This should actually be String...*/ ) : Void {   
		if (this.isReady) {			
			innerIframe.contentWindow.postMessage(message,"*");
		} else {
			postMessageQueue.add(message);
		}
	}
	
	public function terminate() : Void {    
		js.Lib.document.body.removeChild(this.outerIframe);
	}
}