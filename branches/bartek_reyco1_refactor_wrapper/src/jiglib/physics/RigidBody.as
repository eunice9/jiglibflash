/*
Copyright (c) 2007 Danny Chapman 
http://www.rowlhouse.co.uk

This software is provided 'as-is', without any express or implied
warranty. In no event will the authors be held liable for any damages
arising from the use of this software.
Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it
freely, subject to the following restrictions:
1. The origin of this software must not be misrepresented; you must not
claim that you wrote the original software. If you use this software
in a product, an acknowledgment in the product documentation would be
appreciated but is not required.
2. Altered source versions must be plainly marked as such, and must not be
misrepresented as being the original software.
3. This notice may not be removed or altered from any source
distribution.
 */

/**
 * @author Muzer(muzerly@gmail.com)
 * @link http://code.google.com/p/jiglibflash
 */

package jiglib.physics {
	import jiglib.plugin.PhysicsBody;	
	import jiglib.cof.JConfig;
	import jiglib.geometry.JSegment;
	import jiglib.math.JMatrix3D;
	import jiglib.math.JNumber3D;
	import jiglib.plugin.ISkin3D;	

	public class RigidBody implements PhysicsBody {
		private static var idCounter:int = 0;

		private var _id:int;
		private var _skin:ISkin3D;

		protected var _currState:PhysicsState;
		private var _oldState:PhysicsState;
		private var _storeState:PhysicsState;
		private var _invOrientation:JMatrix3D;
		private var _currLinVelocityAux:JNumber3D;
		private var _currRotVelocityAux:JNumber3D;

		private var _mass:Number;
		private var _invMass:Number;
		private var _bodyInertia:JMatrix3D;
		private var _bodyInvInertia:JMatrix3D;
		private var _worldInertia:JMatrix3D;
		private var _worldInvInertia:JMatrix3D;

		private var _force:JNumber3D;
		private var _torque:JNumber3D;

		private var _velChanged:Boolean;
		private var _activity:Boolean;
		private var _movable:Boolean;
		private var _origMovable:Boolean;
		private var _inactiveTime:Number;

		private var _bodiesToBeActivatedOnMovement:Array;

		private var _storedPositionForActivation:JNumber3D;
		private var _lastPositionForDeactivation:JNumber3D;
		private var _lastOrientationForDeactivation:JMatrix3D;

		public var collisions:Array;
		private var _material:MaterialProperties;

		
		protected var _type:String;
		protected var _boundingSphere:Number;

		public function RigidBody(skin:ISkin3D) {
			_id = idCounter++;
			 
			_skin = skin;
			_material = new MaterialProperties();
			 
			_bodyInertia = JMatrix3D.IDENTITY;
			_bodyInvInertia = JMatrix3D.inverse(_bodyInertia);
			 
			_currState = new PhysicsState();
			_oldState = new PhysicsState();
			_storeState = new PhysicsState();
			_invOrientation = JMatrix3D.inverse(_currState.orientation);
			_currLinVelocityAux = new JNumber3D();
			_currRotVelocityAux = new JNumber3D();
			 
			_force = new JNumber3D();
			_torque = new JNumber3D();
	    	 
			// Can this be 'true' by default? 
			// This was set when the 'mov' paremeter from constructor was removed [bartekd]
			_origMovable = true;
			_velChanged = false;
			_inactiveTime = 0;
			 
			_activity = true;
			_movable = true;
			 
			collisions = new Array();
			_storedPositionForActivation = new JNumber3D();
			_bodiesToBeActivatedOnMovement = new Array();
			_lastPositionForDeactivation = _currState.position.clone();
			_lastOrientationForDeactivation = JMatrix3D.clone(_currState.orientation);
			
			_type = "Object3D";
			_boundingSphere = 0;
		}

		public function setOrientation(orient:JMatrix3D):void {
			_currState.orientation.copy(orient);
			_invOrientation = JMatrix3D.transpose(_currState.orientation);
			_worldInertia = JMatrix3D.multiply(JMatrix3D.multiply(_currState.orientation, _bodyInertia), _invOrientation);
			_worldInvInertia = JMatrix3D.multiply(JMatrix3D.multiply(_currState.orientation, _bodyInvInertia), _invOrientation);
		}

		public function get x():Number { 
			return _currState.position.x; 
		}
		public function get y():Number { 
			return _currState.position.y; 
		}
		public function get z():Number { 
			return _currState.position.z; 
		}

		public function set x(px:Number):void { 
			_currState.position.x = px; 
			updateState();
		}

		public function set y(py:Number):void { 
			_currState.position.y = py; 
			updateState();
		}

		public function set z(pz:Number):void { 
			_currState.position.z = pz; 
			updateState();
		}

		public function moveTo(pos:JNumber3D):void {
			pos.copyTo(_currState.position);
			setOrientation(_currState.orientation);
			updateState();
		}

		protected function updateState():void {
			_currState.linVelocity = JNumber3D.ZERO;
			_currState.rotVelocity = JNumber3D.ZERO;
			copyCurrentStateToOld();
		}

		public function setVelocity(vel:JNumber3D):void {
			vel.copyTo(_currState.linVelocity);
		}

		public function setAngVel(angVel:JNumber3D):void {
			angVel.copyTo(_currState.rotVelocity);
		}

		public function setVelocityAux(vel:JNumber3D):void {
			vel.copyTo(_currLinVelocityAux);
		}

		public function setAngVelAux(angVel:JNumber3D):void {
			angVel.copyTo(_currRotVelocityAux);
		}

		public function addGravity():void {
			if(!movable) {
				return;
			}
			_force = JNumber3D.add(_force, JNumber3D.multiply(PhysicsSystem.getInstance().gravity, _mass));
			_velChanged = true;
		}

		public function addExternalForces(dt:Number):void {
			addGravity();
		}

		public function addWorldTorque(t:JNumber3D):void {
			if(!movable) {
				return;
			}
			_torque = JNumber3D.add(_torque, t);
			_velChanged = true;
			setActive();
		}

		public function addWorldForce(f:JNumber3D, p:JNumber3D):void {
			if(!movable) {
				return;
			}
			_force = JNumber3D.add(_force, f);
			addWorldTorque(JNumber3D.cross(f, JNumber3D.sub(p, _currState.position)));
			_velChanged = true;
			setActive();
		}

		public function addBodyForce(f:JNumber3D, p:JNumber3D):void {
			if(!movable) {
				return;
			}
			JMatrix3D.multiplyVector(_currState.orientation, f);
			JMatrix3D.multiplyVector(_currState.orientation, p);
			addWorldForce(f, JNumber3D.add(_currState.position, p));
		}

		public function addBodyTorque(t:JNumber3D):void {
			if(!movable) {
				return;
			}
			JMatrix3D.multiplyVector(_currState.orientation, t);
			addWorldTorque(t);
		}

		public function clearForces():void {
			_force = JNumber3D.ZERO;
			_torque = JNumber3D.ZERO;
		}

		public function applyWorldImpulse(impulse:JNumber3D, pos:JNumber3D):void {
			if(!movable) {
				return;
			}
			_currState.linVelocity = JNumber3D.add(_currState.linVelocity, JNumber3D.multiply(impulse, _invMass));
			
			var rotImpulse:JNumber3D = JNumber3D.cross(impulse, JNumber3D.sub(pos, _currState.position));
			JMatrix3D.multiplyVector(_worldInvInertia, rotImpulse);
			_currState.rotVelocity = JNumber3D.add(_currState.rotVelocity, rotImpulse);
			
			_velChanged = true;
		}

		public function applyWorldImpulseAux(impulse:JNumber3D, pos:JNumber3D):void {
			if(!movable) {
				return;
			}
			_currLinVelocityAux = JNumber3D.add(_currLinVelocityAux, JNumber3D.multiply(impulse, _invMass));
			
			var rotImpulse:JNumber3D = JNumber3D.cross(impulse, JNumber3D.sub(pos, _currState.position));
			JMatrix3D.multiplyVector(_worldInvInertia, rotImpulse);
			_currRotVelocityAux = JNumber3D.add(_currRotVelocityAux, rotImpulse);
			
			_velChanged = true;
		}

		public function applyBodyWorldImpulse(impulse:JNumber3D, delta:JNumber3D):void {
			if(!movable) {
				return;
			}
			_currState.linVelocity = JNumber3D.add(_currState.linVelocity, JNumber3D.multiply(impulse, _invMass));
			
			var rotImpulse:JNumber3D = JNumber3D.cross(impulse, delta);
			JMatrix3D.multiplyVector(_worldInvInertia, rotImpulse);
			_currState.rotVelocity = JNumber3D.add(_currState.rotVelocity, rotImpulse);
			
			_velChanged = true;
		}

		public function applyBodyWorldImpulseAux(impulse:JNumber3D, delta:JNumber3D):void {
			if(!movable) {
				return;
			}
			_currLinVelocityAux = JNumber3D.add(_currLinVelocityAux, JNumber3D.multiply(impulse, _invMass));
			
			var rotImpulse:JNumber3D = JNumber3D.cross(impulse, delta);
			JMatrix3D.multiplyVector(_worldInvInertia, rotImpulse);
			_currRotVelocityAux = JNumber3D.add(_currRotVelocityAux, rotImpulse);
			
			_velChanged = true;
		}

		public function updateVelocity(dt:Number):void {
			if (!movable || !isActive()) {
				return;
			}
			_currState.linVelocity = JNumber3D.add(_currState.linVelocity, JNumber3D.multiply(_force, _invMass * dt));
			
			var rac:JNumber3D = JNumber3D.multiply(_torque, dt);
			JMatrix3D.multiplyVector(_worldInvInertia, rac);
			_currState.rotVelocity = JNumber3D.add(_currState.rotVelocity, rac);
			
			_currState.linVelocity = JNumber3D.multiply(_currState.linVelocity, 0.995);
			_currState.rotVelocity = JNumber3D.multiply(_currState.rotVelocity, 0.995);
		}

		public function updatePosition(dt:Number):void {
			if (!movable || !isActive()) {
				return;
			}
			 
			_currState.position = JNumber3D.add(_currState.position, JNumber3D.multiply(_currState.linVelocity, dt));
			
			var dir:JNumber3D = _currState.rotVelocity.clone();
			var ang:Number = dir.modulo;
			if (ang > 0) {
				dir.normalize();
				ang *= dt;
				var rot:JMatrix3D = JMatrix3D.rotationMatrix(dir.x, dir.y, dir.z, ang);
				_currState.orientation = JMatrix3D.multiply(rot, _currState.orientation);
			}
			setOrientation(_currState.orientation);
		}

		public function updatePositionWithAux(dt:Number):void {
			if (!movable || !isActive()) {
				_currLinVelocityAux = JNumber3D.ZERO;
				_currRotVelocityAux = JNumber3D.ZERO;
				return;
			}
			var ga:int = PhysicsSystem.getInstance().gravityAxis;
			if (ga != -1) {
				_currLinVelocityAux.toArray()[(ga + 1) % 3] *= 0;
				_currLinVelocityAux.toArray()[(ga + 2) % 3] *= 0;
			}
			
			_currState.position = JNumber3D.add(_currState.position, JNumber3D.multiply(JNumber3D.add(_currState.linVelocity, _currLinVelocityAux), dt));
			
			var dir:JNumber3D = JNumber3D.add(_currState.rotVelocity, _currRotVelocityAux);
			var ang:Number = dir.modulo;
			if (ang > 0) {
				dir.normalize();
				ang *= dt;
				var rot:JMatrix3D = JMatrix3D.rotationMatrix(dir.x, dir.y, dir.z, ang);
				_currState.orientation = JMatrix3D.multiply(rot, _currState.orientation);
			}
			_currLinVelocityAux = JNumber3D.ZERO;
			_currRotVelocityAux = JNumber3D.ZERO;
			setOrientation(_currState.orientation);
		}

		public function postPhysics(dt:Number):void {
		}

		public function tryToFreeze(dt:Number):void {
			if (!movable || !isActive()) {
				return;
			}
			if (JNumber3D.sub(_currState.position, _lastPositionForDeactivation).modulo > JConfig.posThreshold) {
				_currState.position.copyTo(_lastPositionForDeactivation);
				_inactiveTime = 0;
				return;
			}
			
			var deltaMat:JMatrix3D = JMatrix3D.sub(_currState.orientation, _lastOrientationForDeactivation);
			if (deltaMat.getCols()[0].modulo > JConfig.orientThreshold || deltaMat.getCols()[1].modulo > JConfig.orientThreshold || deltaMat.getCols()[2].modulo > JConfig.orientThreshold) {
				_lastOrientationForDeactivation.copy(_currState.orientation);
				_inactiveTime = 0;
				return;
			}
			if (getShouldBeActive()) {
				return;
			}
			_inactiveTime += dt;
			if (_inactiveTime > JConfig.deactivationTime) {
				_currState.position.copyTo(_lastPositionForDeactivation);
				_lastOrientationForDeactivation.copy(_currState.orientation);
				setInactive();
			}
		}

		public function setMass(m:Number):void {
			_mass = m;
			_invMass = 1 / m;
			
			setInertia(getInertiaProperties(m));
		}

		public function setInertia(i:JMatrix3D):void {
			_bodyInertia = JMatrix3D.clone(i);
			_bodyInvInertia = JMatrix3D.inverse(i);
			
			_worldInertia = JMatrix3D.multiply(JMatrix3D.multiply(_currState.orientation, _bodyInertia), _invOrientation);
			_worldInvInertia = JMatrix3D.multiply(JMatrix3D.multiply(_currState.orientation, _bodyInvInertia), _invOrientation);
		}

		public function isActive():Boolean {
			return _activity;
		}
		
		public function getMovable():Boolean {
			return _movable;
		}

		public function setMovable(mov:Boolean):void {
			_movable = mov;
		}

		public function get movable():Boolean {
			return _movable;
		}

		public function set movable(mov:Boolean):void {
			_movable = mov;
		}

		public function internalSetImmovable():void {
			_origMovable = _movable;
			_movable = false;
		}

		public function internalRestoreImmovable():void {
			_movable = _origMovable;
		}

		public function getVelChanged():Boolean {
			return _velChanged;
		}

		public function clearVelChanged():void {
			_velChanged = false;
		}

		public function setActive(activityFactor:Number = 1):void {
			if (_movable) {
				_activity = true;
				_inactiveTime = (1 - activityFactor) * JConfig.deactivationTime;
			}
		}

		public function setInactive():void {
			if (_movable) {
				_activity = false;
			}
		}

		public function getVelocity(relPos:JNumber3D):JNumber3D {
			return JNumber3D.add(_currState.linVelocity, JNumber3D.cross(relPos, _currState.rotVelocity));
		}

		public function getVelocityAux(relPos:JNumber3D):JNumber3D {
			return JNumber3D.add(_currLinVelocityAux, JNumber3D.cross(relPos, _currRotVelocityAux));
		}

		public function getShouldBeActive():Boolean {
			return ((_currState.linVelocity.modulo > JConfig.velThreshold) || (_currState.rotVelocity.modulo > JConfig.angVelThreshold));
		}

		public function getShouldBeActiveAux():Boolean {
			return ((_currLinVelocityAux.modulo > JConfig.velThreshold) || (_currRotVelocityAux.modulo > JConfig.angVelThreshold));
		}

		public function dampForDeactivation():void {
			var r:Number = 0.5;
			var frac:Number = _inactiveTime / JConfig.deactivationTime;
			if (frac < r) {
				return;
			}
			
			var scale:Number = 1 - ((frac - r) / (1 - r));
			if (scale < 0) {
				scale = 0;
			}
			else if (scale > 1) {
				scale = 1;
			}
			_currState.linVelocity = JNumber3D.multiply(_currState.linVelocity, scale);
			_currState.rotVelocity = JNumber3D.multiply(_currState.rotVelocity, scale);
		}

		public function doMovementActivations():void {
			if (_bodiesToBeActivatedOnMovement.length == 0 || JNumber3D.sub(_currState.position, _storedPositionForActivation).modulo < JConfig.posThreshold) {
				return;
			}
			for (var i:int = 0;i < _bodiesToBeActivatedOnMovement.length; i++ ) {
				PhysicsSystem.getInstance().activateObject(_bodiesToBeActivatedOnMovement[i]);
			}
			_bodiesToBeActivatedOnMovement = new Array();
		}

		public function addMovementActivation(pos:JNumber3D, otherBody:RigidBody):void {
			for (var i:int = 0;i < _bodiesToBeActivatedOnMovement.length; i++ ) {
				if (_bodiesToBeActivatedOnMovement[i] == otherBody) {
					return;
				}
			}
			if (_bodiesToBeActivatedOnMovement.length == 0) {
				_storedPositionForActivation = pos;
			}
			_bodiesToBeActivatedOnMovement.push(otherBody);
		}

		public function setConstraintsAndCollisionsUnsatisfied():void {
			for (var i:String in collisions) {
				collisions[i].satisfied = false;
			}
		}

		public function segmentIntersect(out:Object, seg:JSegment):Boolean {
			return false;
		}

		public function getInertiaProperties(mass:Number):JMatrix3D {
			return new JMatrix3D();
		}

		public function hitTestObject3D(obj3D:RigidBody):Boolean {
			var num1:Number = JNumber3D.sub(_currState.position, obj3D.currentState.position).modulo;
			var num2:Number = _boundingSphere + obj3D.boundingSphere;
			
			if (num1 <= num2) {
				return true;
			}
			
			return false;
		}

		public function copyCurrentStateToOld():void {
			_currState.position.copyTo(_oldState.position);
			_oldState.orientation.copy(_currState.orientation);
			_currState.linVelocity.copyTo(_oldState.linVelocity);
			_currState.rotVelocity.copyTo(_oldState.rotVelocity);
		}

		public function storeState():void {
			_currState.position.copyTo(_storeState.position);
			_storeState.orientation.copy(_currState.orientation);
			_currState.linVelocity.copyTo(_storeState.linVelocity);
			_currState.rotVelocity.copyTo(_storeState.rotVelocity);
		}

		public function restoreState():void {
			_storeState.position.copyTo(_currState.position);
			_currState.orientation.copy(_storeState.orientation);
			_storeState.linVelocity.copyTo(_currState.linVelocity);
			_storeState.rotVelocity.copyTo(_currState.rotVelocity);
			
			setOrientation(_currState.orientation);
		}

		public function get currentState():PhysicsState {
			return _currState;
		}

		public function get oldState():PhysicsState {
			return _oldState;
		}

		public function get id():int {
			return _id;
		}

		public function get type():String {
			return _type;
		}

		public function get skin():ISkin3D {
			return _skin;
		}

		public function get boundingSphere():Number {
			return _boundingSphere;
		}

		public function get force():JNumber3D {
			return _force;
		}

		public function get mass():Number {
			return _mass;
		}

		public function get invMass():Number {
			return _invMass;
		}

		public function get worldInertia():JMatrix3D {
			return _worldInertia;
		}

		public function get worldInvInertia():JMatrix3D {
			return _worldInvInertia;
		}

		public function limitVel():void {
			if(_currState.linVelocity.x < -100) {
				_currState.linVelocity.x = -100;
			}
			else if(_currState.linVelocity.x > 100) {
				_currState.linVelocity.x = 100;
			}
			if(_currState.linVelocity.y < -100) {
				_currState.linVelocity.y = -100;
			}
			else if(_currState.linVelocity.y > 100) {
				_currState.linVelocity.y = 100;
			}
			if(_currState.linVelocity.z < -100) {
				_currState.linVelocity.z = -100;
			}
			else if(_currState.linVelocity.z > 100) {
				_currState.linVelocity.z = 100;
			}
		}

		public function limitAngVel():void {
			if(_currState.rotVelocity.x < -50) {
				_currState.rotVelocity.x = -50;
			}
			else if(_currState.rotVelocity.x > 50) {
				_currState.rotVelocity.x = 50;
			}
			if(_currState.rotVelocity.y < -50) {
				_currState.rotVelocity.y = -50;
			}
			else if(_currState.rotVelocity.y > 50) {
				_currState.rotVelocity.y = 50;
			}
			if(_currState.rotVelocity.z < -50) {
				_currState.rotVelocity.z = -50;
			}
			else if(_currState.rotVelocity.z > 50) {
				_currState.rotVelocity.z = 50;
			}
		}

		public function getTransform():JMatrix3D {
			return _skin.transform;
		}

		public function updateObject3D():void {
			var m:JMatrix3D = JMatrix3D.multiply(JMatrix3D.translationMatrix(_currState.position.x, _currState.position.y, _currState.position.z), _currState.orientation);
			_skin.transform = m;
		}
		
		public function get material():MaterialProperties {
			return _material;
		}
	}
}