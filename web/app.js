// State
let tracking = false;
let currentPosition = null;
let targetLat = null;
let targetLon = null;
let compassHeading = null;
let targetBearing = 0;


const controlButton = document.getElementById('controlButton');
const buttonText = document.getElementById('buttonText');
const permissionButton = document.getElementById('permissionButton');
const compassArrow = document.getElementById('compassArrow');
const statusMessage = document.getElementById('statusMessage');
const compassInfo = document.getElementById('compassInfo');
const currentPosCard = document.getElementById('currentPosCard');

const latInput = document.getElementById('latitude');
const lonInput = document.getElementById('longitude');
const currentLatEl = document.getElementById('currentLat');
const currentLonEl = document.getElementById('currentLon');
const targetBearingEl = document.getElementById('targetBearing');
const currentHeadingEl = document.getElementById('currentHeading');
const distanceEl = document.getElementById('distance');

const isIOS = /iPhone|iPad|iPod/.test(navigator.userAgent);
const iOS13Plus = isIOS && typeof DeviceOrientationEvent !== 'undefined' && typeof DeviceOrientationEvent.requestPermission === 'function';

if (iOS13Plus) {
    permissionButton.style.display = 'block';
}


permissionButton.addEventListener('click', async () => {
    try {
        const permission = await DeviceOrientationEvent.requestPermission();
        if (permission === 'granted') {
            permissionButton.style.display = 'none';
            statusMessage.textContent = 'Permissões concedidas!';
            startCompass();
        } else {
            statusMessage.textContent = 'Permissão negada';
        }
    } catch (error) {
        console.error('Error requesting permission:', error);
        statusMessage.textContent = 'Erro ao solicitar permissão';
    }
});

controlButton.addEventListener('click', () => {
    if (!tracking) {
        startTracking();
    } else {
        stopTracking();
    }
});

function startTracking() {
    targetLat = parseFloat(latInput.value);
    targetLon = parseFloat(lonInput.value);

    if (isNaN(targetLat) || isNaN(targetLon)) {
        alert('Por favor, insira coordenadas válidas');
        return;
    }

    if (targetLat < -90 || targetLat > 90 || targetLon < -180 || targetLon > 180) {
        alert('Coordenadas inválidas');
        return;
    }

    tracking = true;
    controlButton.classList.add('tracking');
    buttonText.textContent = 'Parar Rastreamento';
    compassArrow.classList.remove('inactive');
    compassArrow.classList.add('tracking');
    compassInfo.style.display = 'block';
    currentPosCard.style.display = 'block';
    statusMessage.textContent = 'Rastreando...';

    if (navigator.geolocation) {
        navigator.geolocation.watchPosition(
            updatePosition,
            handleGeoError,
            { enableHighAccuracy: true, maximumAge: 0 }
        );
    } else {
        statusMessage.textContent = 'Geolocalização não suportada';
    }


    if (!iOS13Plus) {
        startCompass();
    }
}

function stopTracking() {
    tracking = false;
    controlButton.classList.remove('tracking');
    buttonText.textContent = 'Iniciar Rastreamento';
    compassArrow.classList.remove('tracking');
    compassArrow.classList.add('inactive');
    statusMessage.textContent = 'Rastreamento pausado';
}

function startCompass() {
    if (window.DeviceOrientationEvent) {
        window.addEventListener('deviceorientationabsolute', handleOrientation, true);
        window.addEventListener('deviceorientation', handleOrientation, true);
    } else {
        statusMessage.textContent = 'Sensor de orientação não disponível';
    }
}

function handleOrientation(event) {
    if (!tracking) return;


    let heading = null;
    if (event.webkitCompassHeading !== undefined) {

        heading = event.webkitCompassHeading;
    } else if (event.alpha !== null) {

        heading = 360 - event.alpha;
    }

    if (heading !== null) {
        compassHeading = heading;
        updateCompass();
    }
}

function updatePosition(position) {
    currentPosition = position;
    currentLatEl.textContent = position.coords.latitude.toFixed(6);
    currentLonEl.textContent = position.coords.longitude.toFixed(6);

    calculateBearingAndDistance();
    updateCompass();
}

function handleGeoError(error) {
    console.error('Geolocation error:', error);
    statusMessage.textContent = 'Erro ao obter localização';
}

function calculateBearingAndDistance() {
    if (!currentPosition || targetLat === null || targetLon === null) return;

    const lat1 = currentPosition.coords.latitude * Math.PI / 180;
    const lat2 = targetLat * Math.PI / 180;
    const lon1 = currentPosition.coords.longitude * Math.PI / 180;
    const lon2 = targetLon * Math.PI / 180;


    const dLon = lon2 - lon1;
    const y = Math.sin(dLon) * Math.cos(lat2);
    const x = Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLon);
    const bearing = Math.atan2(y, x) * 180 / Math.PI;
    targetBearing = (bearing + 360) % 360;


    const dLat = lat2 - lat1;
    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(lat1) * Math.cos(lat2) *
        Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    const distance = 6371000 * c;


    targetBearingEl.textContent = targetBearing.toFixed(0) + '°';
    distanceEl.textContent = formatDistance(distance);
    statusMessage.textContent = `Distância: ${formatDistance(distance)}`;
}

function updateCompass() {
    if (compassHeading === null || !tracking) return;

    currentHeadingEl.textContent = compassHeading.toFixed(0) + '°';


    const rotation = targetBearing - compassHeading;
    compassArrow.style.transform = `rotate(${rotation}deg)`;
}

function formatDistance(meters) {
    if (meters < 1000) {
        return meters.toFixed(0) + ' m';
    } else {
        return (meters / 1000).toFixed(2) + ' km';
    }
}


console.log('🧭 Bússola Georreferenciada PWA');
console.log('iOS:', isIOS);
console.log('iOS 13+:', iOS13Plus);
