// Aplica la configuracion de cada ronda del Lab 5 creando nuevas revisiones de las
// task definitions y actualizando los servicios ECS (equivale a los procedimientos A y B
// del enunciado, pero por CLI). Siempre parte de la revision 1, la que creo CloudFormation.
//
//   node lab5-pruebas/ecs-config.js --ventas=sin-sidecar|solo-retry|completo [--sidecarTag=1.0.0]
//                                   --inventario=falla|sano|reiniciar
//
// Se pueden dar ambos a la vez. Al terminar imprime T0 (hora de arranque de Inventario).
const { execSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const REGION = 'us-east-2';
const CLUSTER = 'Cheapest-lab5-cluster';
const STACK = 'Cheapest-lab5';

const args = Object.fromEntries(
  process.argv.slice(2).map((a) => a.replace(/^--/, '').split('=')),
);

const aws = (cmd) =>
  execSync(`aws ${cmd} --region ${REGION}`, { encoding: 'utf8' }).trim();

const describeTd = (ref) =>
  JSON.parse(
    aws(`ecs describe-task-definition --task-definition ${ref} --query taskDefinition --output json`),
  );

function register(td) {
  const keep = [
    'family', 'taskRoleArn', 'executionRoleArn', 'networkMode', 'containerDefinitions',
    'volumes', 'placementConstraints', 'requiresCompatibilities', 'cpu', 'memory',
    'runtimePlatform',
  ];
  const out = {};
  keep.forEach((k) => {
    if (td[k] !== undefined) out[k] = td[k];
  });
  const file = path.join(os.tmpdir(), `td-${td.family}.json`);
  fs.writeFileSync(file, JSON.stringify(out));
  return JSON.parse(
    aws(
      `ecs register-task-definition --cli-input-json file://${file.replace(/\\/g, '/')} --query taskDefinition.taskDefinitionArn --output json`,
    ),
  );
}

function setEnv(container, name, value) {
  const found = container.environment.find((e) => e.name === name);
  if (found) found.value = value;
  else container.environment.push({ name, value });
}

const output = (key) =>
  aws(
    `cloudformation describe-stacks --stack-name ${STACK} --query Stacks[0].Outputs[?OutputKey==\`${key}\`].OutputValue --output text`,
  );

// Revision base = la que creo CloudFormation en el stack ACTUAL. No se puede asumir ":1":
// al borrar y recrear el stack, ECS sigue numerando las revisiones y la ":1" seria la del stack viejo.
const baseTd = (logicalId) =>
  aws(
    `cloudformation describe-stack-resource --stack-name ${STACK} --logical-resource-id ${logicalId} --query StackResourceDetail.PhysicalResourceId --output text`,
  );

const registry = `${aws('sts get-caller-identity --query Account --output text')}.dkr.ecr.${REGION}.amazonaws.com`;
const services = [];

if (args.ventas) {
  const td = describeTd(baseTd('VentasTaskDef'));
  const ventas = td.containerDefinitions.find((c) => c.name === 'ventas');
  const sidecar = td.containerDefinitions.find((c) => c.name === 'ventas-sidecar');
  if (args.ventas === 'sin-sidecar') {
    td.containerDefinitions = [ventas];
    setEnv(ventas, 'INVENTARIO_BASE_URL', `http://${output('InventarioALBDns')}`);
  } else if (args.ventas === 'solo-retry') {
    sidecar.image = `${registry}/cheapest-ventas-sidecar:1.0.0-solo-retry`;
  } else if (args.ventas === 'completo') {
    sidecar.image = `${registry}/cheapest-ventas-sidecar:${args.sidecarTag || '1.0.1'}`;
  } else {
    throw new Error(`--ventas desconocido: ${args.ventas}`);
  }
  const arn = register(td);
  console.log(`Ventas (${args.ventas}) -> ${arn}`);
  aws(`ecs update-service --cluster ${CLUSTER} --service svc-Cheapest-ventas --task-definition ${arn} --query service.serviceName --output text`);
  services.push('svc-Cheapest-ventas');
}

if (args.inventario) {
  if (args.inventario === 'reiniciar') {
    aws(`ecs update-service --cluster ${CLUSTER} --service svc-Cheapest-inventario --force-new-deployment --query service.serviceName --output text`);
    console.log('Inventario reiniciado (misma revision).');
  } else {
    const td = describeTd(baseTd('InventarioTaskDef'));
    const inv = td.containerDefinitions.find((c) => c.name === 'inventario');
    const falla = args.inventario === 'falla';
    setEnv(inv, 'FAULT_DELAY_MS', falla ? '5000' : '0');
    setEnv(inv, 'RECOVERY_TIME_MS', falla ? '600000' : '60000');
    const arn = register(td);
    console.log(`Inventario (${args.inventario}) -> ${arn}`);
    aws(`ecs update-service --cluster ${CLUSTER} --service svc-Cheapest-inventario --task-definition ${arn} --force-new-deployment --query service.serviceName --output text`);
  }
  services.push('svc-Cheapest-inventario');
}

if (services.length === 0) {
  console.error('Nada que hacer. Use --ventas=... y/o --inventario=...');
  process.exit(1);
}

console.log(`Esperando a que se estabilicen: ${services.join(', ')} (2 a 6 min)...`);
execSync(`aws ecs wait services-stable --cluster ${CLUSTER} --services ${services.join(' ')} --region ${REGION}`, { stdio: 'inherit' });

for (const svc of services) {
  const taskArn = JSON.parse(
    aws(`ecs list-tasks --cluster ${CLUSTER} --service-name ${svc} --desired-status RUNNING --query taskArns --output json`),
  )[0];
  const t = JSON.parse(
    aws(`ecs describe-tasks --cluster ${CLUSTER} --tasks ${taskArn} --query tasks[0] --output json`),
  );
  const started = new Date(t.startedAt);
  const contenedores = t.containers.map((c) => c.name).join(' + ');
  console.log(
    `${svc}: ${t.taskDefinitionArn.split('/').pop()} | contenedores: ${contenedores} | started: ${started.toLocaleTimeString('es-CO')} (${started.toISOString()})`,
  );
  // correr-ronda.ps1 lee de aqui la hora T0 (arranque de Inventario).
  const dir = path.join(__dirname, 'resultados');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, `ultimo_arranque_${svc}.txt`), started.toISOString());
}

