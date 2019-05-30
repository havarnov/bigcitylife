import './main.css';
import { Elm } from './Main.elm';
import registerServiceWorker from './registerServiceWorker';

var mainModule = 'Main';
var app = Elm[mainModule].init({
  node: document.getElementById('root'),
});
var modules = ['Geolocation'];
PortFunnel.subscribe(app, { modules: modules });

registerServiceWorker();